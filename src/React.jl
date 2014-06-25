module React

using Base.Order
using Base.Collections

export Signal, Input, Node, signal, lift, @lift, map, foldl,
       foldr, merge, filter, dropif, droprepeats, dropwhen,
       sampleon, prev, keepwhen, Timing

import Base: push!, foldl, foldr, merge, map,
       show, writemime, filter

# A `Signal{T}` is a time-varying value of type T.
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

# An `Input` is a signal which can be updated explicitly by code external to React.
# All other signal types have implicit update logic.
# `Input` signals can be updated by a call to `push!`.
# An `Input` must be created with an initial value.
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

# An intermediate node. A `Node` can be created by functions
# in this library that return signals.
abstract Node{T} <: Signal{T}

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

type DropWhen{T} <: Node{T}
    rank :: Uint
    children :: Vector{Signal}
    test :: Signal{Bool}
    signal :: Signal{T}
    value :: T
    function DropWhen(test :: Signal{Bool}, default :: T, s :: Signal{T})
        node = new(next_rank(), Signal[], test, s,
                   test.value ? default : s.value)
        add_child!(s, node)
        return node
    end
end

function update{T}(node :: DropWhen{T}, parent :: Signal{T})
    if node.test.value
        return false
    else
        node.value = parent.value
        return true
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

begin
    local isupdating = false
    # Update the value of an Input signal and propagate the
    # change.
    #
    # Args:
    #     input: An Input signal
    #     val: The new value to be set
    # Returns:
    #     nothing
    function push!{T}(input :: Input{T}, val :: T)
        if isupdating
            error("push! must be called asynchronously")
        end
        isupdating = true
        input.value = val

        heap = (Signal, Signal)[] # a min-heap of (child, parent)
        ord = By(a -> a[1].rank)  # ordered topologically by child.rank

        # first dirty parent
        merge_parent = Dict{Merge, Signal}()
        for c in input.children
            if isa(c, Merge)
                merge_parent[c] = input
            end
            heappush!(heap, (c, input), ord)
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
        isupdating = false
        return nothing
    end
end

push!{T}(inp :: Input{T}, val) = push!(inp, convert(T, val))

# The `lift` operator can be used to create a new signal from
# existing signals. The value of the new signal will be the return
# value of a function `f` applied to the current values of the input
# signals.
#
# Args:
#     f: The transformation function
#     output_type: Output type (optional)
#     inputs...: Signals to apply `f` to. Same number as the arity of `f`.
# Returns:
#     a signal which updates when an argument signal updates.
lift(f :: Function, output_type :: Type, inputs :: Signal...) =
    Lift{output_type}(f, inputs...)

lift(f :: Function, output_type :: Type, inputs) =
    Lift{output_type}(f, map(signal, inputs)...)

lift(f :: Function, inputs...) =
    lift(f, Any, inputs...)

# [Fold](http://en.wikipedia.org/wiki/Fold_(higher-order_function)) over time.
# foldl can be used to reduce a signal updates to a signal of an accumulated value.
#
# Args:
#     f: A function that takes its previously returned value as the first argument
#        and the values of the signals as the second argument
#     v0: initial value of the fold
#     signals: as many signals as one less than the arity of f.
# Returns:
#     A signal which updates when one of the argument signals update.
function foldl{T}(f::Function, v0::T, signals::Signal...)
    local a = v0
    lift((b...) -> (a = f(a, b...)), T, signals...)
end

function foldr{T}(f::Function, v0::T, signals::Signal...)
    local a = v0
    lift((b...) -> (a = f(b..., a)), T, signals...)
end

# Keep only updates that return true when applied to a predicate function.
#
# Args:
#     pred: a function of type that returns a boolean value
#     v0:   the value the signal should take if the predicate is not satisfied initially.
#     s:    the signal to be filtered
# Returns:
#     A filtered signal
filter{T}(pred :: Function, v0 :: T, s :: Signal{T}) = Filter{T}(pred, v0, s)
filter(pred :: Function, v0, s) = filter(pred, v0, signal(s))

# Drop updates when the first signal is true.
#
# Args:
#     test: a Signal{Bool} which tells when to drop updates
#     v0:   value to be used if the test signal is true initially
#     s:    the signal to drop updates from
# Return:
#     a signal which updates only when the test signal is false
dropwhen{T}(test :: Signal{Bool}, v0 :: T, s :: Signal{T}) =
    DropWhen{T}(test, v0, s :: Signal)
dropwhen(test, v0, s) = dropwhen(signal(test), v0, signal(s))

# Sample from the second signal every time an update occurs in the first signal
#
# Args:
#     s1: the signal to watch for updates
#     s2: the signal to sample from when s1 updates
# Returns:
#     a of the same type as s2 which updates with s1
sampleon{T, U}(s1 :: Signal{T}, s2 :: Signal{U}) = SampleOn{T, U}(s1, s2)
sampleon(s1, s2) = sampleon(signal(s1), signal(s2))

# Merge multiple signals of the same type. If more than one signals
# update together, the first one gets precedence.
#
# Args:
#     signals...: two or more signals
# Returns:
#     a merged signal
merge{T}(signals :: Signal{T}...) = Merge{T}(signals...)
merge(signals) = merge(map(signal, signals)...)

# Drop repeated updates. To be used on signals of immutable types.
#
# Args:
#     s: the signal to drop repeats from
# Returns:
#     a signal with repeats dropped.
droprepeats{T}(s :: Signal{T}) = DropRepeats{T}(s)
droprepeats(s) = droprepeats(signal(s))

function show{T}(node :: Signal{T})
    show(node.value)
end

function writemime{T}(io :: IO, m :: MIME"text/plain", node :: Signal{T})
    write(io, "[$(typeof(node))] ")
    writemime(io, m, node.value)
end


include("macros.jl")
include("timing.jl")
include("util.jl")

end # module
