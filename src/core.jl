import Base: push!, eltype, close
export AbstractSignal, Signal, CheckedSignal, push!, value, preserve, unpreserve, close

using DataStructures

abstract AbstractSignal{T}

##### Signal #####

const debug_memory = false # Set this to true to debug gc of nodes

const nodes = WeakKeyDict()
const io_lock = ReentrantLock()

if !debug_memory
    type Signal{T} <: AbstractSignal{T}
        value::T
        parents::Tuple
        actions::Vector
        alive::Bool
        preservers::Dict
    end
else
    type Signal{T} <: AbstractSignal{T}
        value::T
        parents::Tuple
        actions::Vector
        alive::Bool
        preservers::Dict
        bt
        function Signal(v, parents, actions, alive, pres)
            n=new(v,parents,actions,alive,pres,backtrace())
            nodes[n] = nothing
            finalizer(n, log_gc)
            n
        end
    end
end

log_gc(n) =
    @async begin
        lock(io_lock)
        print(STDERR, "Signal got gc'd. Creation backtrace:")
        Base.show_backtrace(STDERR, n.bt)
        println(STDOUT)
        unlock(io_lock)
    end

immutable Action
    recipient::WeakRef
    f::Function
end

const action_queue = Queue(Tuple{Signal, Action})

isrequired(a::Action) = (a.recipient.value != nothing) && a.recipient.value.alive

Signal{T}(x::T, parents=()) = Signal{T}(x, parents, Action[], true, Dict{Signal, Int}())
Signal{T}(::Type{T}, x, parents=()) = Signal{T}(x, parents, Action[], true, Dict{Signal, Int}())
# A signal of types
Signal(t::Type) = Signal(Type, t)

parents(s::Signal) = s.parents
preservers(s::Signal) = s.preservers

# preserve/unpreserve nodes from gc
"""
    preserve(signal::AbstractSignal)

prevents `signal` from being garbage collected as long as any of its parents are around. Useful for when you want to do some side effects in a signal.
e.g. `preserve(map(println, x))` - this will continue to print updates to x, until x goes out of scope. `foreach` is a shorthand for `map` with `preserve`.
"""
function preserve(x::AbstractSignal)
    for p in parents(x)
        preservers(p)[x] = get(preservers(p), x, 0)+1
        preserve(p)
    end
    x
end

"""
    unpreserve(signal::AbstractSignal)

allow `signal` to be garbage collected. See also `preserve`.
"""
function unpreserve(x::AbstractSignal)
    for p in parents(x)
        n = get(preservers(p), x, 0)-1
        if n <= 0
            delete!(preservers(p), x)
        else
            preservers(p)[x] = n
        end
        unpreserve(p)
    end
    x
end

Base.show(io::IO, n::Signal) =
    write(io, "Signal{$(eltype(n))}($(n.value), nactions=$(length(n.actions))$(n.alive ? "" : ", closed"))")

value(n::Signal) = n.value
value(::Void) = false
eltype{T}(::Signal{T}) = T
eltype{T}(::Type{Signal{T}}) = T

##### CheckedSignal #######

"""
    CheckedSignal(val, bounds) -> cs

Create a signal `cs` that throws an error if `push!(cs, val)` does not
satisfy `bounds`. `bounds` can be a range object (in which case the
value must be contained within the range) or a function (in which case
`bounds(val)` must be `true`).

A range-checked `CheckedSignal` may be used as an index in a `view`,
in which case `bounds` must be equal to (or contained within) the
indices for the corresponding dimension of the array.

Example:
```julia
A = rand(5, 6)
col = CheckedSignal(1, indices(A, 2))
V = view(A, :, col)  # V == A[:,1]
push!(col, 3)
sleep(0.01)          # to let the Reactive.jl message queue run
# Now V == A[:,3]
```
"""
immutable CheckedSignal{T,B} <: AbstractSignal{T}
    signal::Signal{T}
    bounds::B

    function (::Type{CheckedSignal{T,B}}){T,B}(signal::Signal{T}, bounds::B)
        checkvalue(bounds, signal)
        new{T,B}(signal, bounds)
    end
end
CheckedSignal(value, bounds) = CheckedSignal(Signal(value), bounds)
CheckedSignal{T,B}(signal::Signal{T}, bounds::B) = CheckedSignal{T,B}(signal, bounds)

uncheckedsignal(s::Signal) = s
uncheckedsignal(s::CheckedSignal) = s.signal

bounds(s) = s
bounds(s::CheckedSignal) = s.bounds

checkvalue(bounds, signal::Signal) = checkvalue1(bounds, value(signal))
checkvalue(bounds, val) = checkvalue1(bounds, val)
@inline function checkvalue1(bounds::Range, val)
    checkindex(Bool, bounds, val) || throw_checkederror(bounds, val)
end
@inline function checkvalue1(f::Function, val)
    f(val) || throw_checkederror(f, val)
end
@noinline function throw_checkederror(bounds, val) # @noinline to prevent GC frame alloc.
    # should ideally be InexactError or BoundsError, but those aren't flexible enough
    throw(ArgumentError("CheckedSignal: $val is not within $bounds"))
end
@noinline function throw_checkederror(f::Function, val)
    throw(ArgumentError("CheckedSignal: ($f)($val) was not true"))
end

value(s::CheckedSignal) = value(uncheckedsignal(s))
parents(s::CheckedSignal) = parents(uncheckedsignal(s))
preservers(s::CheckedSignal) = preservers(uncheckedsignal(s))

function Base.push!(s::CheckedSignal, i)
    checkvalue(bounds(s), i)
    push!(uncheckedsignal(s), i)
end

function Base.map(f, s::Union{Signal,CheckedSignal}...)
    map(f, map(uncheckedsignal, s)...)
end


##### Connections #####

function add_action!(f, node, recipient)
    a = Action(WeakRef(recipient), f)
    push!(node.actions, a)
    a
end

function remove_action!(f, node, recipient)
    node.actions = filter(a -> a.f != f, node.actions)
end

function close(n::Signal, warn_nonleaf=true)
    finalize(n) # stop timer etc.
    n.alive = false
    if !isempty(n.actions)
        any(map(isrequired, n.actions)) && warn_nonleaf &&
            warn("closing a non-leaf node is not a good idea")
        empty!(n.actions)
    end

    for p in n.parents
        delete!(p.preservers, n)
    end
end

function send_value!(node::Signal, x, timestep)
    # Dead node?
    !node.alive && return

    # Set the value and do actions
    node.value = x
    for action in node.actions
        action.recipient.value != nothing && #nothing means downstream node has been gc'd
            DataStructures.enqueue!(action_queue, (action.recipient.value, action))
    end
end
send_value!(wr::WeakRef, x, timestep) = wr.value != nothing && send_value!(wr.value, x, timestep)

do_action(a::Action, timestep) =
    isrequired(a) && a.f(a.recipient.value, timestep)

# If any actions have been gc'd, remove them
cleanup_actions(node::Signal) =
    node.actions = filter(isrequired, node.actions)


##### Messaging #####

const CHANNEL_SIZE = 1024

immutable Message
    node
    value
    onerror::Function
end

# Global channel for signal updates
const _messages = Channel{Nullable{Message}}(CHANNEL_SIZE)


"""
`push!(signal, value, onerror=Reactive.print_error)`

Queue an update to a signal. The update will be propagated when all currently
queued updates are done processing.

The third optional argument is a callback to be called in case the update
ends in an error. The callback receives 3 arguments: the signal, the value,
and a `CapturedException` with the fields `ex` which is the original exception
object, and `processed_bt` which is the backtrace of the exception.

The default error callback will print the error and backtrace to STDERR.
"""
Base.push!(n::Signal, x, onerror=print_error) = _push!(n, x, onerror)

function _push!(n, x, onerror=print_error)
    taken = Base.n_avail(_messages)
    if taken >= CHANNEL_SIZE
        warn("Message queue is full. Ordering may be incorrect.")
        @async put!(_messages, Message(n, x, onerror))
    else
        put!(_messages, Message(n, x, onerror))
    end
    nothing
end
_push!(::Void, x, onerror=print_error) = nothing

const timestep = Ref{Int}(0)

function break_loop()
    put!(_messages, Nullable{Message}())
end

function stop()
    run_till_now() # process all remaining events
    break_loop()
end


"""
Processes `n` messages from the Reactive event queue.
"""
function run(n::Int=typemax(Int))
    ts = timestep[]
    try
        for i=1:n
            ts += 1
            message = take!(_messages)
            isnull(message) && break # ignore emtpy messages

            msgval = get(message)
            try
                send_value!(msgval.node, msgval.value, ts)
                while length(action_queue) > 0
                    (node, action) = DataStructures.dequeue!(action_queue)
                    do_action(action, ts)
                end
            catch err
                if isa(err, InterruptException)
                    println("Reactive event loop was inturrupted.")
                    rethrow()
                else
                    bt = catch_backtrace()
                    msgval.onerror(msgval.node, msgval.value, CapturedException(err, bt))
                end
            end
        end
    finally
        timestep[] = ts
    end
end

# Default error handler function
function print_error(node, value, ex)
    lock(io_lock)
    io = STDERR
    println(io, "Failed to push!")
    print(io, "    ")
    show(io, value)
    println(io)
    println(io, "to node")
    print(io, "    ")
    show(io, node)
    println(io)
    showerror(io, ex)
    println(io)
    unlock(io_lock)
end

# Run everything queued up till the instant of calling this function
run_till_now() = run(Base.n_avail(_messages))

# A decent default runner task
function __init__()
    global runner_task = @async begin
        Reactive.run()
    end
end
