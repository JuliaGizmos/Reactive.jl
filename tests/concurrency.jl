using Base.Test
using Reactive

a = Input(0)

function crash(x)
    push!(a, 1)
end

b = lift(crash, a)
# don't specify exception type, to remain compatible with 0.2
@test_throws ErrorException push!(a, 1)
