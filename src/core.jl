import Base: push!, eltype, close
export Signal, push!, value, close

##### Node #####

const debug_memory = false # Set this to true to debug gc of nodes

const nodes = WeakKeyDict()
const io_lock = ReentrantLock()

if !debug_memory
    type Node{T}
        value::T
        parents::Tuple
        actions::Vector
        alive::Bool
    end
else
    type Node{T}
        value::T
        parents::Tuple
        actions::Vector
        alive::Bool
        bt
        function Node(v, parents, actions, alive)
            n=new(v,parents,actions,alive,backtrace())
            nodes[n] = nothing
            finalizer(n, log_gc)
            n
        end
    end
end

typealias Signal Node

log_gc(n) =
    @async begin
        lock(io_lock)
        print(STDERR, "Node got gc'd. Creation backtrace:")
        Base.show_backtrace(STDERR, n.bt)
        println(STDOUT)
        unlock(io_lock)
    end

immutable Action
    recipient::Node
    f::Function
end
isrequired(a::Action) = a.recipient.alive

Node{T}(x::T, parents=()) = Node{T}(x, parents, Action[], true)
Node{T}(::Type{T}, x, parents=()) = Node{T}(x, parents, Action[], true)

# preserve/unpreserve nodes from gc
const _nodes = ObjectIdDict()
preserve(x::Node) = (_nodes[x] = get(_nodes,x,0)+1; x)
function unpreserve(x::Node)
    v = _nodes[x]
    v == 1 ? pop!(_nodes,x) : (_nodes[x] = v-1)
    nothing
end

Base.show(io::IO, n::Node) =
    write(io, "Signal{$(eltype(n))}($(n.value), nactions=$(length(n.actions))$(n.alive ? "" : ", closed"))")

value(n::Node) = n.value
value(::Void) = false
eltype{T}(::Node{T}) = T
eltype{T}(::Type{Node{T}}) = T

##### Connections #####

function add_action!(f, node, recipient)
    a = Action(recipient, f)
    push!(node.actions, a)
    a
end

function remove_action!(f, node, recipient)
    node.actions = filter(a -> a.f != f, node.actions)
end

function close(n::Node, warn_nonleaf=true)
    finalize(n) # stop timer etc.
    n.alive = false
    if !isempty(n.actions)
        any(map(isrequired, n.actions)) && warn_nonleaf &&
            warn("closing a non-leaf node is not a good idea")
        empty!(n.actions)
    end
end

function send_value!(node::Node, x, timestep)
    # Dead node?
    !node.alive && return

    # Set the value and do actions
    node.value = x
    for action in node.actions
        do_action(action, timestep)
    end
end
send_value!(wr::WeakRef, x, timestep) = send_value!(wr.value, x, timestep)

do_action(a::Action, timestep) =
    isrequired(a) && a.f(a.recipient, timestep)

# If any actions have been gc'd, remove them
cleanup_actions(node::Node) =
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
Base.push!(n::Node, x, onerror=print_error) = _push!(n, x, onerror)

function _push!(n, x, onerror=print_error)
    taken = Base.n_avail(_messages)
    if taken >= CHANNEL_SIZE
        warn("Message queue is full. Ordering may be incorrect.")
        @async put!(_messages, (n, x, onerror))
    else
        put!(_messages, (n, x, onerror))
    end
    nothing
end
_push!(::Void, x, onerror=print_error) = nothing

# remove messages from the channel and propagate them
global run
let timestep = 0
    function run(steps=typemax(Int))
        runner_task = current_task()::Task
        local waiting, node, value, onerror, iter = 1
        try
            while iter <= steps
                timestep += 1
                iter += 1

                waiting = true
                (node, value, onerror) = take!(_messages)
                waiting = false

                send_value!(node, value, timestep)
            end
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
