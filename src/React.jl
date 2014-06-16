module React

using Base.Order
using Base.Collections

export Signal, Input, Node, signal, lift, map, foldl,
       foldr, merge, filter, droprepeats, sampleon

import Base: push!, foldl, foldr, merge, map,
       show, writemime, filter

# A signal is a value that can change over time.
abstract Signal{T}

# A topological order
begin
    local counter = uint(0)

    function next_rank()
        counter += 1
        return counter
    end
end

signal(x :: Signal) = x

# An input is a root node in the signal graph.
# It must be created with a default value, and can be
# updated with a call to `update`.
type Input{T} <: Signal{T}
    rank :: Uint
    children :: Vector{Signal}
    value :: T

    function Input(v :: T)
        self = new(next_rank(), Signal[], v)
        return self
    end
end
Input{T}(val :: T) = Input{T}(val)

abstract Node{T} <: Signal{T} # An intermediate node

function add_child!(parents :: (Signal...), child :: Signal)
    for p in parents
        push!(p.children, child)
    end
end
add_child!(parent :: Signal, child :: Signal) = push!(parent.children, child)

type Lift{T} <: Node{T}
    rank :: Uint
    children :: Vector{Signal}
    f :: Function
    signals :: (Signal...)
    value :: T
    function Lift(f :: Function, signals :: Signal...)
        node = new(next_rank(), Signal[], f, signals,
                   convert(T, f([s.value for s in signals]...)))
        add_child!(signals, node)
        return node
    end
end

function update{T, U}(node :: Lift{T}, parent :: Signal{U})
    node.value = convert(T, node.f([s.value for s in node.signals]...))
    return true
end

type Filter{T} <: Node{T}
    rank :: Uint
    children :: Vector{Signal}
    predicate :: Function
    signal :: Signal{T}
    value :: T
    function Filter(predicate :: Function, v0 :: T, s :: Signal{T})
        node = new(next_rank(), Signal[], predicate, s,
                   predicate(s.value) ?
                   s.value : v0)
        add_child!(s, node)
        return node
    end
end

function update{T}(node :: Filter{T}, parent :: Signal{T})
    if node.predicate(node.signal.value)
        node.value = node.signal.value
        return true
    else
        return false
    end
end

type DropRepeats{T} <: Node{T}
    rank :: Uint
    children :: Vector{Signal}
    signal :: Signal{T}
    value :: T
    function DropRepeats(s :: Signal{T})
        node = new(next_rank(), Signal[], s, s.value)
        add_child!(s, node)
        return node
    end
end

function update{T}(node :: DropRepeats{T}, parent :: Signal{T})
    if node.value != parent.value
        node.value = parent.value
        return true
    else
        return false
    end
end

type Merge{T} <: Node{T}
    rank :: Uint
    children :: Vector{Signal}
    signals :: (Signal{T}...)
    ranks :: Dict{Signal, Int}
    value :: T
    function Merge(signals :: Signal...)
        if length(signals) < 1
            error("Merge requires at least one as argument.")
        end
        fst, _ = signals
        node = new(next_rank(), Signal[], signals,
                   Dict{Signal, Int}(), fst.value)
        for (r, s) in enumerate(signals)
            node.ranks[s] = r # precedence
        end
        add_child!(signals, node)
        return node
    end
end

function update{T}(node :: Merge{T}, parent :: Signal{T})
    node.value = parent.value
    return true
end

type SampleOn{T, U} <: Node{U}
    rank :: Uint
    children :: Vector{Signal}
    signal1 :: Signal{T}
    signal2 :: Signal{U}
    value :: U
    function SampleOn(signal1, signal2)
        node = new(next_rank(), Signal[], signal1, signal2, signal2.value)
        add_child!(signal1, node)
        return node
    end
end

function update{T, U}(node :: SampleOn{T, U}, parent :: Signal{T})
    node.value = node.signal2.value
    return true
end

function push!{T}(inp :: Input{T}, val :: T)
    inp.value = val

    heap = (Signal, Signal)[] # a min-heap of (child, parent)
    ord = By(a -> a[1].rank)  # ordered topologically by child.rank

    # first dirty parent
    merge_parent = Dict{Merge, Signal}()
    for c in inp.children
        if isa(c, Merge)
            merge_parent[c] = inp
        end
        heappush!(heap, (c, inp), ord)
    end

    prev = nothing
    while !isempty(heap)
        (n, parent) = heappop!(heap, ord)
        if n == prev
            continue # already processed
        end

        # Merge is a special case!
        if isa(n, Merge) && haskey(merge_parent, n)
            propagate = update(n, merge_parent[n])
        else
            propagate = update(n, parent)
        end

        if propagate
            for c in n.children
                if isa(c, Merge)
                    if haskey(merge_parent, c)
                        if c.ranks[n] < c.ranks[merge_parent[c]]
                            merge_parent[c] = n
                        end
                    else
                        merge_parent[c] = n
                    end
                end
                heappush!(heap, (c, n), ord)
            end
        end
        prev = n
    end
end
push!{T}(inp :: Input{T}, val) = push!(inp, convert(T, val))

lift(f :: Function, output_type :: Type, inputs :: Signal...) =
    Lift{output_type}(f, inputs...)

lift(f :: Function, output_type :: Type, inputs) =
    Lift{output_type}(f, map(signal, inputs)...)

lift(f :: Function, inputs...) =
    lift(f, Any, inputs...)

sampleon{T, U}(s1 :: Signal{T}, s2 :: Signal{U}) = SampleOn{T, U}(s1, s2)
sampleon(s1, s2) = sampleon(signal(s1), signal(s2))
filter{T}(pred :: Function, v0 :: T, s :: Signal{T}) = Filter{T}(pred, v0, s)
merge{T}(signals :: Signal{T}...) = Merge{T}(signals...)
merge(signals) = merge(map(signal, signals)...)
droprepeats{T}(s :: Signal{T}) = DropRepeats{T}(s :: Signal)
droprepeats(s) = droprepeats(signal(s))

function foldl{T}(f::Function, v0::T, s::Signal)
    local a = v0
    lift(b -> (a = f(a, b)), T, s)
end

function foldr{T}(f::Function, v0::T, s::Signal)
    local a = v0
    lift(b -> (a = f(b, a)), T, s)
end

#############################################
# Methods for displaying signals

function show{T}(node :: Signal{T})
    show(node.value)
end

function writemime{T}(io :: IO, m :: MIME"text/plain", node :: Signal{T})
    write(io, "[$(typeof(node))] ")
    writemime(io, m, node.value)
end

end # module
