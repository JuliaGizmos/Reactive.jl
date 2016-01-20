import Base: push!, eltype, close
export Signal, push!, value, preserve, unpreserve, close

##### Signal #####

const debug_memory = false # Set this to true to debug gc of nodes

const nodes = WeakKeyDict()
const io_lock = ReentrantLock()

if !debug_memory
    type Signal{T}
        value::T
        parents::Tuple
        actions::Vector
        alive::Bool
        preservers::Dict
    end
else
    type Signal{T}
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
isrequired(a::Action) = a.recipient.value != nothing && a.recipient.value.alive

Signal{T}(x::T, parents=()) = Signal{T}(x, parents, Action[], true, Dict{Signal, Int}())
Signal{T}(::Type{T}, x, parents=()) = Signal{T}(x, parents, Action[], true, Dict{Signal, Int}())
# A signal of types
Signal(t::Type) = Signal(Type, t)

# preserve/unpreserve nodes from gc
"""
    preserve(signal::Signal)

prevents `signal` from being garbage collected as long as any of its parents are around. Useful for when you want to do some side effects in a signal.
e.g. `preserve(map(println, x))` - this will continue to print updates to x, until x goes out of scope. `foreach` is a shorthand for `map` with `preserve`.
"""
function preserve(x::Signal)
    for p in x.parents
        p.preservers[x] = get(p.preservers, x, 0)+1
        preserve(p)
    end
    x
end

"""
    unpreserve(signal::Signal)

allow `signal` to be garbage collected. See also `preserve`.
"""
function unpreserve(x::Signal)
    for p in x.parents
        n = get(p.preservers, x, 0)-1
        if n <= 0
            delete!(p.preservers, x)
        else
            p.preservers[x] = n
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
        do_action(action, timestep)
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

# Global channel for signal updates
const _messages = Channel{Any}(CHANNEL_SIZE)

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
        @async put!(_messages, (n, x, onerror))
    else
        put!(_messages, (WeakRef(n), x, onerror))
    end
    nothing
end
_push!(::Void, x, onerror=print_error) = nothing

# remove messages from the channel and propagate them
global run
let timestep = 0
    function run(steps=typemax(Int))
        runner_task = current_task()::Task
        iter = 1
        while iter <= steps
            timestep += 1
            iter += 1

            let message = take!(_messages)
                node, value, onerror = message
                try
                    send_value!(node, value, timestep)
                catch err
                    if isa(err, InterruptException)
                        println("Reactive event loop was inturrupted.")
                        rethrow()
                    else
                        bt = catch_backtrace()
                        onerror(node, value, CapturedException(err, bt))
                    end
                end
            end
        end
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
