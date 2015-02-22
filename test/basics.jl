using FactCheck
using Reactive

number() = int(rand()*1000)


## Basics

facts("Basic checks") do

    a = Input(number())
    b = lift(x -> x*x, a)

    context("lift") do

        # Lift type
        @fact typeof(b) => Reactive.Lift{Int}

        # type conversion
        push!(a, 1.0)
        @fact b.value => 1
        # InexactError to be precise
        @fact_throws push!(a, 1.1)

        push!(a, number())
        @fact b.value => a.value*a.value

        push!(a, -number())
        @fact b.value => a.value*a.value

        ## Multiple inputs to Lift
        c = lift(+, Int, a, b)
        @fact c.value => a.value + b.value

        push!(a, number())
        @fact c.value => a.value+b.value

        push!(a, number())
        @fact c.value => a.value+b.value
    end


    context("merge") do

        ## Merge
        d = Input(number())
        e = merge(d, b, a)

        # precedence to d
        @fact e.value => d.value

        push!(a, number())
        # precedence to b over a
        @fact e.value => b.value
    end

    context("foldl") do

        ## foldl over time
        push!(a, 0)
        f = foldl(+, 0, a)
        nums = int(rand(100)*1000)
        map(x -> push!(a, x), nums)

        @fact sum(nums) => f.value
    end

    context("filter") do
        # filter
        g = Input(0)
        pred = x -> x % 2 != 0
        h = filter(pred, 1, g)

        @fact h.value => 1

        push!(g, 2)
        @fact h.value => 1

        push!(g, 3)
        @fact h.value => 3
    end

    context("sampleon") do
        # sampleon
        g = Input(0)

        push!(g, number())
        i = Input(true)
        j = sampleon(i, g)
        # default value
        @fact j.value => g.value
        push!(g, g.value-1)
        @fact j.value => g.value+1
        push!(i, true)
        @fact j.value => g.value
    end

    context("droprepeats") do
        # droprepeats
        count = s -> foldl((x, y) -> x+1, 0, s)

        k = Input(1)
        l = droprepeats(k)

        @fact l.value => k.value
        push!(k, 1)
        @fact l.value => k.value
        push!(k, 0)
        #println(l.value, " ", k.value)
        @fact l.value => k.value

        m = count(k)
        n = count(l)

        seq = [1, 1, 1, 0, 1, 0, 1, 0, 0]
        map(x -> push!(k, x), seq)

        @fact m.value => length(seq)
        @fact n.value => 6
    end

    context("dropwhen") do
        # dropwhen
        b = Input(true)
        n = Input(1)
        dw = dropwhen(b, 0, n)
        @fact dw.value => 0
        push!(n, 2)
        @fact dw.value => 0
        push!(b, false)
        @fact dw.value => 0
        push!(n, 1)
        @fact dw.value => 1
        push!(n, 2)
        @fact dw.value => 2
        dw = dropwhen(b, 0, n)
        @fact dw.value => 2
    end
end
