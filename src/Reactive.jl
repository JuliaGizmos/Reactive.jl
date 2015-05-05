module Reactive

using Compat
using Base.Order
using Base.Collections

export SignalSource, Signal, Input, Node, signal, value, lift, @lift, map, foldl,
       flatten, switch, foldr, merge, filter, dropif, droprepeats, dropwhen,
       sampleon, prev, keepwhen, ⟿

import Base: eltype, join_eltype, convert, push!, merge, map, show, writemime, filter

if VERSION >= v"0.3-"
    import Base: foldl, foldr
end

typealias Callable Union(DataType, Function)

# SignalSource is a contract that you can call signal() on the
# value to get a Signal
abstract SignalSource

# A `Signal{T}` is a time-varying value of type T.
# Signal itself is a subtype of SignalSource for easy
# dispatch (e.g. see foldl below)
abstract Signal{T} <: SignalSource
signal(x::Signal) = x

convert(::Type{Signal}, x::SignalSource) = signal(x)
eltype{T}(::Signal{T}) = T

# A topological order
begin
    local counter = @compat UInt(0)

    function next_rank()
        counter += 1
        return counter
    end
end

rank(x::Signal) = x.rank # topological rank
value(x::Signal) = x.value # current value

# An `Input` is a signal which can be updated explicitly by code external to Reactive.
# All other signal types have implicit update logic.
# `Input` signals can be updated by a call to `push!`.
# An `Input` must be created with an initial value.
type Input{T} <: Signal{T}
    rank::Uint
    children::Vector{Signal}
    value::T

    function Input(v)
        new(next_rank(), Signal[], convert(T, v))
    end
end
Input{T}(v::T) = Input{T}(v)

# An intermediate node. A `Node` can be created by functions
# in this library that return signals.
abstract Node{T} <: Signal{T}

#function add_child!(parents::Tuple{Vararg{Signal}}, child::Signal)
function add_child!(parents::@compat(Tuple{Vararg{Signal}}), child::Signal)
    for p in parents
        push!(p.children, child)
    end
end
add_child!(parent::Signal, child::Signal) = push!(parent.children, child)

function remove_child!(parents::(@compat Tuple{Vararg{Signal}}), child::Signal)
    for p in parents
        p.children = p.children[find(p.children .!= child)]
    end
end
remove_child!(parent::Signal, child::Signal) =
    remove_child!((parent,), child)

type Lift{T} <: Node{T}
    rank::Uint
    children::Vector{Signal}
    f::Callable
    signals::@compat Tuple{Vararg{Signal}}
    value::T

    function Lift(f::Callable, signals, init)
        node = new(next_rank(), Signal[], f, signals, convert(T, init))
        add_child!(signals, node)
        return node
    end
end

function update{T}(node::Lift{T}, parent)
    node.value = convert(T, node.f([s.value for s in node.signals]...))
    return true
end

type Filter{T} <: Node{T}
    rank::Uint
    children::Vector{Signal}
    predicate::Function
    signal::Signal{T}
    value::T

    function Filter(predicate, v0, s::Signal{T})
        node = new(next_rank(), Signal[], predicate, s,
                   predicate(s.value) ?
                   s.value : convert(T, v0))
        add_child!(s, node)
        return node
    end
end

function update{T}(node::Filter{T}, parent::Signal{T})
    if node.predicate(node.signal.value)
        node.value = node.signal.value
        return true
    else
        return false
    end
end

type DropWhen{T} <: Node{T}
    rank::Uint
    children::Vector{Signal}
    test::Signal{Bool}
    signal::Signal{T}
    value::T

    function DropWhen(test, v0, s::Signal{T})
        node = new(next_rank(), Signal[], test, s,
                   test.value ? convert(T, v0) : s.value)
        add_child!(s, node)
        return node
    end
end

function update{T}(node::DropWhen{T}, parent::Signal{T})
    if node.test.value
        return false
    else
        node.value = parent.value
        return true
    end
end

type DropRepeats{T} <: Node{T}
    rank::Uint
    children::Vector{Signal}
    signal::Signal{T}
    value::T

    function DropRepeats(s)
        node = new(next_rank(), Signal[], s, s.value)
        add_child!(s, node)
        return node
    end
end

function update{T}(node::DropRepeats{T}, parent::Signal{T})
    if node.value != parent.value
        node.value = parent.value
        return true
    else
        return false
    end
end

type Merge{T} <: Node{T}
    rank::Uint
    children::Vector{Signal}
    signals::@compat Tuple{Vararg{Signal}}
    ranks::Dict{Signal, Int}
    value::T
    function Merge(signals::@compat Tuple{Vararg{Signal}})
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

function update{T}(node::Merge{T}, parent)
    node.value = convert(T, parent.value)
    return true
end

type SampleOn{T, U} <: Node{U}
    rank::Uint
    children::Vector{Signal}
    signal1::Signal{T}
    signal2::Signal{U}
    value::U
    function SampleOn(signal1, signal2)
        node = new(next_rank(), Signal[], signal1, signal2, signal2.value)
        add_child!(signal1, node)
        return node
    end
end

function update(node::SampleOn, parent)
    node.value = node.signal2.value
    return true
end

deepvalue(s::Signal) = value(s)
deepvalue{T <: Signal}(s::Signal{T}) = deepvalue(value(s))

type Flatten{T} <: Node{T}
    rank::Uint
    children::Vector{Signal}
    value::T
    function Flatten(signalsignal::Signal)
        node = new(next_rank(), Signal[], deepvalue(signalsignal))

        firstsig = value(signalsignal)
        add_child!(signalsignal, node)
        foldl(begin add_child!(firstsig, node); firstsig end, signalsignal; output_type=Any) do prev, next
            remove_child!(prev, node)
            add_child!(next, node)
            next
        end

        return node
    end
end

function update(node::Flatten, parent)
    node.value = deepvalue(parent)
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
    function push!{T}(input::Input{T}, val)
        if isupdating
            error("push! called when another signal is still updating.")
        else
            try
                isupdating = true
                input.value = convert(T, val)

                heap = (@compat Tuple{Signal, Signal})[] # a min-heap of (child, parent)
                child_rank(x) = rank(x[1])
                ord = By(child_rank)  # ordered topologically by child.rank

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
            catch ex
                # FIXME: Rethink this.
                isupdating = false
                showerror(STDERR, ex)
                println(STDERR)
                Base.show_backtrace(STDERR, catch_backtrace())
                println(STDERR)
                throw(ex)
            end
        end
    end
end

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

lift(f::Callable, inputs::Signal...; init=f(map(value, inputs)...)) =
    Lift{typeof(init)}(f, inputs, init)

lift(f::Callable, output_type::Type, inputs::Signal...; init=f(map(value, inputs)...)) =
    Lift{output_type}(f, inputs, init)

lift(f::Callable, output_type::Type, inputs::SignalSource...; kwargs...) =
    lift(f, output_type, map(signal, inputs)...; kwargs...)

lift(f::Callable, inputs::SignalSource...; kwargs...) =
    lift(f, map(signal, inputs)...; kwargs...)

# Uncomment in Julia >= 0.3 to enable cute infix operators.
#     ⟿(signals::(Any...), f::Callable) = lift(f, signals...)
#     ⟿(signal, f::Callable) = lift(f, signal)
#     function ⟿(signals::Union(Any, (Any, Callable))...)
#         last = signals[end]
#         ss = [signals[1:end-1]..., last[1]]
#         f  = last[2]
#         (ss...) ⟿ f
#     end

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
function foldl{T}(f, v0::T, signal::SignalSource, signals::SignalSource...; output_type=T)
    local a = v0
    lift((b...) -> a = f(a, b...),
        output_type, signal, signals...; init=v0)
end

function foldr{T}(f::Function, v0::T, signal::SignalSource, signals::SignalSource...; output_type=T)
    local a = v0
    lift((b...) -> a = f(b..., a),
        output_type, signal, signals...; init=v0)
end

# Keep only updates that return true when applied to a predicate function.
#
# Args:
#     pred: a function of type that returns a boolean value
#     v0:   the value the signal should take if the predicate is not satisfied initially.
#     s:    the signal to be filtered
# Returns:
#     A filtered signal
filter{T}(pred::Function, v0, s::Signal{T}) = Filter{T}(pred, v0, s)
filter(pred::Function, v0, s::SignalSource) = filter(pred, v0, signal(s))

# Drop updates when the first signal is true.
#
# Args:
#     test: a Signal{Bool} which tells when to drop updates
#     v0:   value to be used if the test signal is true initially
#     s:    the signal to drop updates from
# Return:
#     a signal which updates only when the test signal is false
dropwhen{T}(test::Signal{Bool}, v0, s::Signal{T}) =
    DropWhen{T}(test, v0, s)

# Sample from the second signal every time an update occurs in the first signal
#
# Args:
#     s1: the signal to watch for updates
#     s2: the signal to sample from when s1 updates
# Returns:
#     a of the same type as s2 which updates with s1
sampleon{T, U}(s1::Signal{T}, s2::Signal{U}) = SampleOn{T, U}(s1, s2)
sampleon(s1::SignalSource, s2::SignalSource) = sampleon(signal(s1), signal(s2))

# Merge multiple signals of the same type. If more than one signals
# update together, the first one gets precedence.
#
# Args:
#     signals...: two or more signals
# Returns:
#     a merged signal
merge(signals::Signal...) = Merge{join_eltype(signals...)}(signals)
merge(signals::SignalSource...) = merge(map(signal, signals))

# Drop repeated updates. To be used on signals of immutable types.
#
# Args:
#     s: the signal to drop repeats from
# Returns:
#     a signal with repeats dropped.
droprepeats{T}(s::Signal{T}) = DropRepeats{T}(s)
droprepeats(s::SignalSource) = droprepeats(signal(s))

function show{T}(io::IO, node::Signal{T})
    write(io, string("[$(typeof(node))] ", node.value))
end

#
# Flatten a signal of signal into a signal
#
# Args:
#    ss: the signal of signals
# Returns:
#    A signal
#
flatten(ss::Signal; typ=eltype(value(ss))) =
    Flatten{typ}(ss)

#
# `switch(f, switcher)` is the same as `flatten(lift(f, switcher))`
#
# Args:
#    f: A function from `T` to `Signal`
#    switcher: A signal of type `T`
# Returns:
#    A flattened signal
#
switch(f, switcher) =
    lift(f, switcher) |> flatten

function writemime{T}(io::IO, m::MIME"text/plain", node::Signal{T})
    writemime(io, m, node.value)
end

include("macros.jl")
include("timing.jl")
include("util.jl")

end # module
