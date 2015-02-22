using Reactive
using FactCheck

facts("@lift") do
    a = Input(1)
    b = @lift a^2
    context("@lift basics") do
        @fact a.value^2 => b.value

        push!(a, 2)

        @fact a.value^2 => b.value
    end

    t1 = @lift (a,)
    t2 = @lift (a, b)
    l1 = @lift [a]
    l2 = @lift [a, b^2]
    c1 = @lift {a}

    push!(a, 3)

    context("@lift evaluation") do
        @fact t1.value => (a.value,)
        @fact t2.value => (a.value, b.value)
        @fact l1.value => [a.value]
        @fact l2.value => [a.value, b.value^2]
        @fact c1.value =>  {a.value}
    end

    # test use in a function
    context("@lift inside a function") do
        k = 3
        f(a,b) = @lift a + b + 1 + k

        z = f(a,b)
        push!(a, 3)
        @fact a.value^2 + a.value + 4 => z.value
    end

end
