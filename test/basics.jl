using FactCheck
using Reactive

step() = Reactive.run(1)
queue_size() = Base.n_avail(Reactive._messages)
number() = round(Int, rand()*1000)

## Basics

facts("Basic checks") do
    x = Signal(Float32)
    @test isa(x, Signal{Type{Float32}})
    
    a = Signal(number())
    b = map(x -> x*x, a)

    context("map") do

        # Lift type
        #@fact typeof(b) --> Reactive.Lift{Int}

        # type conversion
        push!(a, 1.0)
        step()
        @fact value(b) --> 1
        # InexactError to be precise
        push!(a, 2.1, (n,x,error_node,err) -> @fact n --> a)
        step()

        @fact value(b) --> 1

        push!(a, number())
        step()
        @fact value(b) --> value(a)^2

        push!(a, -number())
        step()
        @fact value(b) --> value(a)^2

        ## Multiple inputs to Lift
        c = map(+, a, b, typ=Int)
        @fact value(c) --> value(a) + value(b)

        push!(a, number())
        step()
        @fact value(c) --> value(a) + value(b)

        push!(b, number())
        step()
        @fact value(c) --> value(a) + value(b)
    end


    context("merge") do

        ## Merge
        d = Signal(number())
        e = merge(d, b, a)

        # precedence to d
        @fact value(e) --> value(d)

        push!(a, number())
        step()
        # precedence to b over a -- a is older.
        @fact value(e) --> value(b)

        c = map(identity, a) # Make a younger than b
        f = merge(d, c, b)
        push!(a, number())
        step()
        @fact value(f) --> value(c)
    end

    context("foldp") do

        ## foldl over time
        gc()
        push!(a, 0)
        step()
        f = foldp(+, 0, a)
        nums = round(Int, rand(100)*1000)
        map(x -> begin push!(a, x); step() end, nums)

        @fact sum(nums) --> value(f)
    end

    context("filter") do
        # filter
        g = Signal(0)
        pred = x -> x % 2 != 0
        h = filter(pred, 1, g)
        j = filter(x -> x % 2 == 0, 1, g)

        @fact value(h) --> 1
        @fact value(j) --> 0

        push!(g, 2)
        step()
        @fact value(h) --> 1

        push!(g, 3)
        step()
        @fact value(h) --> 3
    end

    context("sampleon") do
        # sampleon
        g = Signal(0)

        push!(g, number())
        step()
        i = Signal(true)
        j = sampleon(i, g)
        # default value
        @fact value(j) --> value(g)
        push!(g, value(g)-1)
        step()
        @fact value(j) --> value(g)+1
        push!(i, true)
        step()
        @fact value(j) --> value(g)
    end

    context("droprepeats") do
        # droprepeats
        count = s -> foldp((x, y) -> x+1, 0, s)

        k = Signal(1)
        l = droprepeats(k)

        @fact value(l) --> value(k)
        push!(k, 1)
        step()
        @fact value(l) --> value(k)
        push!(k, 0)
        step()
        #println(l.value, " ", value(k))
        @fact value(l) --> value(k)

        m = count(k)
        n = count(l)

        seq = [1, 1, 1, 0, 1, 0, 1, 0, 0]
        map(x -> begin push!(k, x); step() end, seq)

        @fact value(m) --> length(seq)
        @fact value(n) --> 6
    end

    context("filterwhen") do
        # filterwhen
        b = Signal(false)
        n = Signal(1)
        dw = filterwhen(b, 0, n)
        @fact value(dw) --> 0
        push!(n, 2)
        step()
        @fact value(dw) --> 0
        push!(b, true)
        step()
        @fact value(dw) --> 0
        push!(n, 1)
        step()
        @fact value(dw) --> 1
        push!(n, 2)
        step()
        @fact value(dw) --> 2
        dw = filterwhen(b, 0, n)
        @fact value(dw) --> 2
    end

    context("push! inside push!") do
        a = Signal(0)
        b = Signal(1)
        Reactive.preserve(map(x -> push!(a, x), b))

        @fact value(a) --> 0

        step()
        @fact value(a) --> 1

        push!(a, 2)
        step()
        @fact value(a) --> 2
        @fact value(b) --> 1

        push!(b, 3)
        step()
        @fact value(b) --> 3
        @fact value(a) --> 2

        step()
        @fact value(a) --> 3
    end

    context("previous") do
        x = Signal(0)
        y = previous(x)
        @fact value(y) --> 0

        push!(x, 1)
        step()

        @fact value(y) --> 0

        push!(x, 2)
        step()

        @fact value(y) --> 1

        push!(x, 3)
        step()

        @fact value(y) --> 2
        @fact queue_size() --> 0
    end


    context("delay") do
        x = Signal(0)
        y = delay(x)
        @fact value(y) --> 0

        push!(x, 1)
        step()

        @fact queue_size() --> 1
        @fact value(y) --> 0

        step()
        @fact value(y) --> 1
    end


    context("bindind") do
        x = Signal(0)
        y = Signal(0)
        bind!(y,x,false)

        push!(x,1000)
        step()

        @fact value(y) --> 1000

        unbind!(y,x,false)
        push!(x,0)
        step()

        @fact value(y) --> 1000
    end
end
