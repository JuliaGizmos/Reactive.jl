module React

export Signal, Input, lift, update, reduce

import Base.reduce, Base.show, Base.merge

# A signal is a value that can change over time.
abstract Signal{T}

typealias Time Float64

# Unique ID
typealias UID Int

begin
    local last_id = 0
    guid() = last_id += 1
end

# Root nodes of the graph
roots = Signal[]

# An input is a root node in the signal graph.
# It must be created with a default value, and can be
# updated with a call to `update`.
type Input{T} <: Signal{T}
    id :: UID
    children :: Set{Signal}
    value :: T

    function Input(v :: T)
        self = new(guid(), Set{Signal}(), v)
        append!(roots, [self])
        return self
    end
end
Input{T}(val :: T) = Input{T}(val)

type Node{T} <: Signal{T}
    id :: UID
    children :: Set{Signal}
    node_type :: Symbol
    value :: T

    recv :: Function

    function Node(val :: T, node_type=:Node)
        new(guid(), Set{Signal}(), node_type, val)
    end
end

function send{T}(node :: Signal{T}, timestep :: Time, changed :: Bool)
    for child in node.children
        child.recv(timestep, changed, node)
    end
end

# recv is called by update
function recv{T}(inp :: Input{T}, timestep :: Time,
                 originator :: Signal, val :: T)
    # Forward it to children
    changed = originator == inp
    if changed
        inp.value = val
    end
    send(inp, timestep, changed)
end

# update method on an Input updates its value
# and notifies all dependent signals
function update{T}(inp :: Input{T}, value :: T)
    timestep = time()
    for node in roots
        recv(node, timestep, inp, value)
    end
end

function lift(output_type :: DataType, f :: Function,
              inputs :: Signal...)
    local count = 0,
          n = length(inputs),
          ischanged = false # accumulate change info
    apply_f() = apply(f, [i.value for i in inputs])
    node = Node{output_type}(apply_f(), :lift)

    function recv(timestep :: Time, changed :: Bool, parent :: Signal)
        count += 1
        if changed
            ischanged = true
        end

        if count == n
            if ischanged
                # counting makes sure apply_f is called
                # just once in a given timestep
                node.value = apply_f()
            end
            send(node, timestep, ischanged)
            ischanged = false
            count = 0
        end
    end
    node.recv = recv

    for i in inputs
        push!(i.children, node)
    end
    return node
end

lift(f :: Function, inputs :: Signal...) = lift(Any, f, inputs...)

# reduce over a stream of updates
function reduce{T}(f :: Function, signal :: Signal{T}, v0 :: T)
    local a = v0
    function foldp(b)
        a = f(a, b)
    end
    lift(T, foldp, signal)
end

# merge signals
function merge{T}(signals :: Signal{T}...)

    first, _ = signals
    node = Node{T}(first.value, :merge)
    rank = {n => i for (i, n) in enumerate(signals)}
    
    local n = length(signals), count = 0, ischanged = false,
          minrank = n+1, val = node.value

    function recv(timestep :: Time, changed :: Bool, parent :: Signal)
        count += 1
        if changed
            ischanged = true
            if haskey(rank, parent)
                if minrank > rank[parent]
                    val = parent.value
                    minrank = rank[parent]
                end
            end
        end
        if count == n
            if ischanged
                node.value = val
                minrank = n+1
            end
            send(node, timestep, ischanged)
            ischanged = false
            count = 0
        end
    end

    for sig in signals
        push!(sig.children, node)
    end
    node.recv = recv

    return node
end

# TODO:
# Abort propogation from inside a Lift
# Eliminate redundancy when lifted arguments depend on the same Input

end # module
