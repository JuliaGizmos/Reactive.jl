module React

export Signal, Input, Lift, update, reduce

import Base.reduce

# A signal is a value that can change over time.
abstract Signal{T}

# Unique ID
typealias UID Int
begin
    local last_id = 0
    guid() = last_id += 1
end

# Signal graph
children = Dict{Signal, Set{Signal}}()

# An input is a root node in the signal graph.
# It must be created with a default value, and can be
# updated with a call to `update`.
type Input{T} <: Signal{T}
    id :: UID
    value :: T
    function Input(val :: T)
        self = new(guid(), val) # A signal requires a default value
        children[self] = Set{Signal}()
        return self
    end
end
Input{T}(val :: T) = Input{T}(val)

# A Lift transforms many input signals into another signal
# Lift is constructed with a function of arity N and N signals
# whose values act as the input to the function
type Lift{T} <: Signal{T}
    id :: UID
    value :: T
    update :: Function
    
    function Lift(f :: Function, inputs :: Signal...)
        apply_f() = f([s.value for s in inputs]...) :: T
        self = new(guid(), apply_f(), apply_f)
        children[self] = Set{Signal}()

        for s in inputs
            push!(children[s], self)
        end
        return self
    end
end
Lift(f :: Function, inputs :: Signal...) = Lift{Any}(f, inputs...)

# update method on an Input updates its value
# and notifies all dependent signals
function update{T}(inp :: Input{T}, value :: T)
    inp.value = value
    for c in children[inp]
        notify(c, inp)
    end
end

function notify{T, U}(node :: Lift{T}, source :: Signal{U})
    node.value = node.update() # recompute node
    for c in children[node]
        notify(c, node)
    end
end

# reduce over a stream of updates
function reduce{T}(f :: Function, signal :: Signal{T}, v0 :: T)
    local a = v0
    function foldp(b)
        a = f(a, b)
    end
    Lift{T}(foldp, signal)
end

# merge two signals
function merge{T}(f :: Function, s1 :: Signal{T}, s2 :: Signal{T})
    node = Lift{T}(x->x)
end

# TODO:
# Abort propogation from inside a Lift
# Eliminate redundancy when lifted arguments depend on the same Input

end # module
