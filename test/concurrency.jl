using Base.Test
using Reactive

a = Input(0)

function crash(x)
    push!(a, 1)
end

facts("push! inside push!") do
    b = consume(crash, a)
    @fact push!(a, 1)
end
