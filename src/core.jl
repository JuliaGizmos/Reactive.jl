import Base: push!, eltype, close
export Signal, Input, Node, push!, value, close

##### Node #####

immutable Action
    recipient::WeakRef
    f::Function
end
isrequired(a::Action) = a.recipient.value != nothing && a.recipient.value.alive

type Node{T}
    value::T
    parents::Tuple
    actions::Vector{Action}
    alive::Bool
end
Node(x, parents=()) = Node(x, parents, Action[], true)
Node{T}(::Type{T}, x, parents=()) = Node{T}(x, parents, Action[], true)

# preserve/unpreserve nodes from gc
const _nodes = ObjectIdDict()
preserve(x::Node) = _nodes[x] = get(_nodes,x,0)+1
function unpreserve(x::Node)
    v = _nodes[x]
    v == 1 ? pop!(_nodes,x) : (_nodes[x] = v-1)
    nothing
end

typealias Signal Node
typealias Input Node

Base.show(io::IO, n::Node) =
    write(io, "Node{$(eltype(n))}($(n.value), nactions=$(length(n.actions))$(n.alive ? "" : ", closed"))")
 
value(n::Node) = n.value
eltype{T}(::Node{T}) = T
eltype{T}(::Type{Node{T}}) = T

##### Connections #####
 
function add_action!(f, node, recipient)
    push!(node.actions, Action(WeakRef(recipient), f))
end

function remove_action!(f, node, recipient)
    node.actions = filter(a -> a.f != f, node.actions)
end

if VERSION < v"0.4.0-dev"
    include("finalize_compat.jl")
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

function send_value!(node, x, timestep)
    # Dead node?
    !node.alive && return

    # Set the value and do actions
    node.value = x
    for action in node.actions
        do_action(action, timestep)
    end
end

do_action(a::Action, timestep) =
    isrequired(a) && a.f(a.recipient.value, timestep)

# If any actions have been gc'd, remove them
cleanup_actions(node::Node) =
    node.actions = filter(isrequired, node.actions)


##### Messaging #####

if VERSION < v"0.4.0-dev"
     using MessageUtils
     queue_size(x) = length(fetch(x.rr).space)
else
    channel(;sz=1024) = Channel{Any}(sz)
    queue_size = Base.n_avail
end

const CHANNEL_SIZE = 1024

# Global channel for signal updates
const _messages = channel(sz=CHANNEL_SIZE)

# queue an update. meta comes back in a ReactiveException if there is an error
function Base.push!(n::Node, x; meta::Any=nothing)
    taken = queue_size(_messages)
    if taken >= CHANNEL_SIZE
        warn("Message queue is full. Ordering may be incorrect.")
        @async put!(_messages, (n, x, meta))
    else
        put!(_messages, (n, x, meta))
    end
    nothing
end

include("exception.jl")

# remove messages from the channel and propagate them
global runner_task
global run
let timestep = 0
    function run(steps=typemax(Int))
        runner_task = current_task()::Task
        local waiting, node, value, debug_meta, iter = 1
        try
            while iter <= steps
                timestep += 1
                iter += 1

                waiting = true
                (node, value, debug_meta) = take!(_messages)
                waiting = false

                send_value!(node, value, timestep)
            end
        catch err
            bt = catch_backtrace()
            throw(ReactiveException(waiting, node, value, timestep, debug_meta, CapturedException(err, bt)))
        end
    end
end

# Run everything queued up till the instant of calling this function
run_till_now() = run(queue_size(_messages))
