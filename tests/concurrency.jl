using Base.Test
using React

a = Input(0)

function crash(x)
    push!(a, 1)
end

b = lift(crash, a)
@test_throws ErrorException push!(a, 1)
