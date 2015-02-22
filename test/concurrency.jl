using Base.Test
using Reactive

a = Input(0)

function crash(x)
    push!(a, 1)
end

facts("push! inside push!") do
    b = lift(crash, a)
    @fact_throws push!(a, 1)
end
