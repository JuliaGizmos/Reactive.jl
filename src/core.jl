import Base: push!, eltype, consume
export Signal, Input, Node, push!, value, step
 
##### Node #####
 
type Node{T}
    value::T
    actions::Vector{WeakRef}
    alive::Bool
end
Node(x) = Node(x, WeakRef[], true)
Node{T}(::Type{T}, x) = Node{T}(x, WeakRef[], true)
 
typealias Signal Node
typealias Input Node

Base.show(io::IO, n::Node) =
    write(io, "Node{$(eltype(n))}($(n.value), nactions=$(length(n.actions))$(n.alive ? "" : ", killed!"))")
 
value(n::Node) = n.value
eltype{T}(::Node{T}) = T
eltype{T}(::Type{Node{T}}) = T
kill(n::Node) = (n.alive = false; n)
 
##### Connections #####
 
const _recipients_dict = WeakKeyDict()

function add_action!(f, node, recipient)
    push!(node.actions, WeakRef(f))

    # hold on to the actions for nodes still in scope
    if haskey(_recipients_dict, recipient)
        push!(_recipients_dict[recipient], f)
    else
        _recipients_dict[recipient] = [f]
    end
end

function send_value!(node, x, timestep)
    # Dead node?
    !node.alive && return

    # Set the value and do actions
    node.value = x
    for action in node.actions
        do_action(action.value, timestep)
     end
end

# Nothing is a weakref gone stale.
do_action(f::Nothing, timestep) = nothing
do_action(f::Function, timestep) = f(timestep)

# If any actions have been gc'd, remove them
cleanup_actions(node::Node) =
    node.actions = filter(n -> n.value != nothing, node.actions)


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
function Base.push!(n::Node, x; meta=nothing)
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
global run
let timestep = 0
    function run(steps=typemax(Int))
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
