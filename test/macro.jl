using Reactive
using FactCheck
using Compat

a = Input(2)
b = @lift a^2
facts("@lift") do

    context("@lift input expressions") do

        t1 = @lift (a,)
        t2 = @lift (a, b)
        l1 = @lift [a]
        l2 = @lift [a, b]
        c1 = @lift Any[a]

        push!(a, 3)

        @fact t1.value => (a.value,)
        @fact t2.value => (a.value, b.value)
        @fact l1.value => [a.value]
        @fact l2.value => [a.value, b.value]
        @fact c1.value => Any[a.value]
    end
    context("@lift basics") do
        @fact value(a)^2 => value(b)

        push!(a, 3)

        @fact a.value^2 => b.value
    end

    # test use in a function
    context("@lift inside a function") do
        k = 3
       # f(a,b) = @lift a + b + 1 + k
  
       # z = f(a,b)
       # push!(a, 4)
       # @fact a.value^2 + a.value + 4 => z.value
    end

end
