import Base: push!, eltype, close
export Signal, push!, value, preserve, unpreserve, close, rename!

using DataStructures

##### Signal #####

const debug_memory = false # Set this to true to debug gc of nodes

const nodeset = WeakKeyDict()
const io_lock = ReentrantLock()

const runner_task = Ref{Task}()

const run_remove_dead_nodes = Ref(false)

const CHANNEL_SIZE = Ref(1024)

#run in asynchronous mode by default
const async_mode = Ref(true)

const debug_mode = Ref(false)

const nodes = WeakRef[] #stores the nodes in order of creation (which is a topological order for execution of the nodes' actions)

const edges = Vector{Int}[] #parents to children, useful for plotting graphs

const node_count = Dict{String, Int}() #counts of different signals for naming


if !debug_memory
    mutable struct Signal{T}
        id::Int # also its index into `nodes`, and `edges`
        value::T
        parents::Tuple
        active::Bool
        actions::Vector{Function}
        preservers::Dict
        name::String
        function Signal{T}(v, parents, pres, name) where T
            id = length(nodes) + 1
            n=new{T}(id, v, parents, false, Function[], pres, name)
            push!(nodes, WeakRef(n))
            push!(edges, Int[])
            foreach(p->push!(edges[p.id], id), parents)
            finalizer(schedule_node_cleanup, n)
            n
        end
    end
else
    mutable struct  Signal{T}
        id::Int
        value::T
        parents::Tuple
        active::Bool
        actions::Vector
        preservers::Dict
        name::String
        bt
        function Signal{T}(v, parents, actions, pres, name) where T
            id = length(nodes) + 1
            n=new{T}(id, v, parents, false, Function[], pres, name, backtrace())
            push!(nodes, WeakRef(n))
            push!(edges, Int[])
            foreach(p->push!(edges[p.id], id), parents)
            nodeset[n] = nothing
            finalizer(log_gc, n)
            n
        end
    end
end

Signal(x::T, parents=(); name::String = auto_name!("input")) where {T} =
    Signal{T}(x, parents, Dict{Signal, Int}(), name)
Signal(::Type{T}, x, parents=(); name::String = auto_name!("input")) where {T} =
    Signal{T}(x, parents, Dict{Signal, Int}(), name)
# A signal of types
Signal(t::Type{T}; name::String = auto_name!("input")) where {T} = Signal(Type{T}, t, name=name)

function log_gc(n)
    @async begin
        lock(io_lock)
        print(stderr, "Signal got gc'd. Creation backtrace:")
        Base.show_backtrace(stderr, n.bt)
        println(STDOUT)
        unlock(io_lock)
    end
end



function auto_name!(name, parents...)
    parents_str = join(map(s->s.name, parents), ", ")
    isempty(parents_str) || (name *= "($parents_str)")
    count = get!(node_count, name, 0) + 1
    node_count[name] = count
    countstr = count > 1 ? "-$(node_count[name])" : ""
    "$name$countstr"
end

"""
`rename!(s::Signal, name::String)`

Change a Signal's name
"""
function rename!(s::Signal, name::String)
    s.name = name
end

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

function Base.show(io::IO, n::Signal)
    active_str = isactive(n) ? "(active)" : ""
    print(io, n.id, ": \"", n.name, "\" = ")
    print(io, something(n.value, "nothing"))
    print(io, ' ', eltype(n), ' ', active_str)
end

value(n) = n
value(n::Signal) = n.value
value(::Nothing) = false

eltype(::Signal{T}) where {T} = T
eltype(::Type{Signal{T}}) where {T} = T

##### Connections #####
const restart_queue = Ref(false)
function add_action!(f, node)
    push!(node.actions, f)
    if current_task() !== runner_task[]
        maybe_restart_queue()
    else
        restart_queue[] = true
    end
    f
end

"""
Removes `action` from `node.actions`
"""
function remove_action!(node, action)
    filter!(a -> a != action, node.actions)
    nothing
end

"""
Schedule a cleanup of dead nodes - called as a finalizer on each GC'd node
"""
function schedule_node_cleanup(n)
    run_remove_dead_nodes[] = true
end

"""
Remove GC'd nodes from `nodes`, is run before push! when scheduled.
Not thread-safe in the sense that if it is run while other code is iterating
through `nodes`, e.g. in run_push, iteration could skip nodes.
"""
function remove_dead_nodes!()
    allnodes = [] # keep a ref to all nodes to avoid GC whilst in this function
    filter!(nodes) do noderef
        node = noderef.value
        node != nothing && push!(allnodes, node)
        node != nothing
    end
    foreach((i_n)->((i,n) = i_n; n.id = i), enumerate(allnodes)) # renumber nodes
    reinit_edges!(allnodes)
    nothing
end

function reinit_edges!(allnodes)
    empty!(edges)
    foreach(n->push!(edges, []), allnodes)
    foreach(allnodes) do n
        foreach(p-> push!(edges[p.id], n.id), n.parents)
    end
    nothing
end

function close(n::Signal, warn_nonleaf=true)
    for p in n.parents
        delete!(p.preservers, n)
    end
    finalize(n) # stop timer, schedule_node_cleanup, etc.
end

set_value!(node::Signal, x) = (node.value = x)

##### Messaging #####
struct Message
    node
    value
    onerror::Function
end
struct NullException <: Exception
end
# Global channel for signal updates
struct MaybeMessage
    isnull::Bool
    data::Message
    MaybeMessage() = new(true)
    MaybeMessage(m::Message) = new(false, m)
end

Base.get(x::MaybeMessage) = isnull(x) ? throw(NullException()) : x.data
if VERSION < v"0.7.0-alpha.2"
    import Base: isnull
end
isnull(x::MaybeMessage) = x.isnull
Base.convert(::Type{MaybeMessage}, x::Message) = MaybeMessage(x)

const _messages = Channel{MaybeMessage}(CHANNEL_SIZE[])

run_async(async::Bool) = (async_mode[] = async)

"""
`push!(signal, value, onerror=Reactive.print_error)`

Queue an update to a signal. The update will be propagated when all currently
queued updates are done processing.

The third (optional) argument, `onerror`, is a callback triggered when
the update ends in an error. The callback receives 4 arguments,
`onerror(sig, val, node, capex)`, where `sig` and `val` are the Signal
and value that `push!` was called with, respectively, `node` is the
Signal whose action triggered the error, and `capex` is a
`CapturedException` with the fields `ex` which is the original
exception object, and `processed_bt` which is the backtrace of the
exception.

The default error callback will print the error and backtrace to stderr.
"""
function Base.push!(n::Signal, x, onerror = print_error)
    if async_mode[]
        async_push!(n, x, onerror)
    else
        run_push(n, x, onerror)
    end
end

function async_push!(n, x, onerror=print_error)
    taken = Base.n_avail(_messages)
    if taken >= CHANNEL_SIZE[]
        @warn "Message queue is full. Ordering may be incorrect. "*
        "Channel size can be increased by setting `ENV[\"REACTIVE_CHANNEL_SIZE\"] = ...` before `using Reactive`."
        @async put!(_messages, Message(n, x, onerror))
    else
        put!(_messages, Message(n, x, onerror))
    end
    nothing
end

function break_loop()
    put!(_messages, MaybeMessage())
end

function stop()
    run_till_now() # process all remaining events
    break_loop()
    # it seems to take a long time until the runner_task is actually finished
    # which can be enough to run into maybe_restart_queue with !isdone(runner_task)
    # see #144
    fetch(runner_task[])
end

"""
Processes `n` messages from the Reactive event queue.
"""
function run(n::Int=typemax(Int))
    for i=1:n
        message = take!(_messages)

        isnull(message) && break # break on null messages

        msgval = get(message)
        run_push(msgval.node, msgval.value, msgval.onerror)
        restart_queue[] && maybe_restart_queue()
    end
end

set_debug_mode(val = true) = (debug_mode[] = val)

runaction(f) = f()

activate!(node::Signal) = (node.active = true)
deactivate!(node::Signal) = (node.active = false)
isactive(node::Signal) = node.active

isactive(deadnode::Nothing) = false

activate!(noderef::WeakRef) = (noderef.value != nothing &&
                                (noderef.value.active = true))

deactivate!(noderef::WeakRef) = (noderef.value != nothing &&
                                (noderef.value.active = false))

isactive(noderef::WeakRef) = (noderef.value != nothing && noderef.value.active)

"""
A node's actions should be run if any of its parents are active, since that
generally means one (or more) of the parent nodes' values have changed. If the
node doesn't have actions, don't set it to active, since its value won't be
updated, meaning the update propagation can stop. N.b. The non-active when node
has no actions mechanism is relied on for correct behaviour by fpswhen, and
possibly other operators, i.e. it is not just an optimisation.
"""
function run_node(node::Signal)
    if any(isactive, node.parents) && length(node.actions) > 0
        activate!(node)
        foreach(runaction, node.actions)
    end
end

function run_push(pushnode::Signal, val, onerror, dont_remove_dead = false)
    node = pushnode # ensure node is set for error reporting - see onerror below
    try
        if run_remove_dead_nodes[] && !dont_remove_dead
            run_remove_dead_nodes[] = false
            remove_dead_nodes!()
        end
        set_value!(pushnode, val)
        activate!(pushnode)

        # run the actions for all downstream nodes
        for noderef in nodes[pushnode.id:end]
            noderef.value == nothing && continue
            node = noderef.value # node must be set here - see onerror call below
            run_node(node)
        end

        # reset active status to false for pushnode and all downstream nodes
        for noderef in nodes[pushnode.id:end]
            noderef.value == nothing && continue
            deactivate!(noderef.value)
        end
    catch err
        if isa(err, InterruptException)
            @info("Reactive event loop was inturrupted.")
            rethrow()
        else
            bt = catch_backtrace()
            try
                onerror(pushnode, val, node, CapturedException(err, bt))
            catch err_onerror
                if isa(err_onerror, MethodError)
                    println(stderr, "The syntax for `onerror` has changed, see ?push!")
                end
                rethrow()
            end
        end
    end
end

# Default error handler function
function print_error(pushnode, val, error_node, ex)
    lock(io_lock)
    io = stderr
    println(io, "Failed to push!")
    print(io, "    ")
    show(io, val)
    println(io)
    println(io, "to node")
    print(io, "    ")
    show(io, pushnode)
    println(io)
    println(io)
    println(io, "error at node: $error_node")
    showerror(io, ex)
    println(io)
    unlock(io_lock)
end

function onerror_rethrow(pushnode, val, error_node, ex)
    rethrow()
end

# Run everything queued up till the instant of calling this function
run_till_now() = run(Base.n_avail(_messages))

# Works around world age problems (see issue #131)
function maybe_restart_queue()
    if !istaskdone(runner_task[])
        break_loop()
        if current_task() === runner_task[]
            # will happen if `add_action!` is called while processing a push!
            prev_runner = current_task()
            @async begin
                # new runner should fetch for current runner to process the
                # break_loop (null) message
                fetch(prev_runner)
                runner_task[] = current_task()
                run()
            end
        else
            fetch(runner_task[])
            runner_task[] = @async run()
        end
    end
    restart_queue[] = false
end

function __init__()
    if haskey(ENV, "REACTIVE_CHANNEL_SIZE")
        CHANNEL_SIZE[] = parse(Int, ENV["REACTIVE_CHANNEL_SIZE"])
    end
    runner_task[] = @async run()
end
