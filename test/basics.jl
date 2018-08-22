using Reactive

## Basics

@testset "Basic checks" begin
    x = Signal(Float32)
    @test (isa(x, Signal{Type{Float32}})) == (true)

    a = Signal(number(); name="a")
    b = map(x -> x*x, a; name="b")

    @testset "map" begin

        # Lift type
        #@test (typeof(b)) == (Reactive.Lift{Int})

        # type conversion
        push!(a, 1.0)
        step()
        @test (value(b)) == (1)
        # InexactError to be precise
        push!(a, 2.1, (n,x,error_node,err) -> @test (n) == (a))
        step()

        @test (value(b)) == (1)

        push!(a, number())
        step()
        @test (value(b)) == (value(a)^2)

        push!(a, -number())
        step()
        @test (value(b)) == (value(a)^2)

        ## Multiple inputs to Lift
        d = Signal(number())
        c = map(+, a, b, d, typ=Int)
        @test (value(c)) == (value(a) + value(b) + value(d))

        push!(a, number())
        step()
        @test (value(c)) == (value(a) + value(b) + value(d))


        push!(d, number())
        step()
        @test (value(c)) == (value(a) + value(b) + value(d))
    end


    @testset "merge" begin
        ## Merge
        d = Signal(number(); name="d")
        e = merge(b, d, a; name="e")

        # precedence to d
        @test (value(e)) == (value(d))

        push!(a, number())
        step()
        # precedence to b over a -- a is older.

        @test (value(e)) == (value(b))

        c = map(identity, a) # Make a younger than b
        f = merge(d, c, b)
        push!(a, number())
        step()
        @test (value(f)) == (value(c))
    end

    @testset "foldp" begin

        ## foldl over time

        GC.gc()
        push!(a, 0)
        step()
        f = foldp(+, 0, a)
        nums = round.([Int], rand(100)*1000)
        map(x -> begin push!(a, x); step() end, nums)

        @test (sum(nums)) == (value(f))
    end

    @testset "filter" begin
        # filter
        g = Signal(0)
        pred = x -> x % 2 != 0
        h = filter(pred, 1, g)
        j = filter(x -> x % 2 == 0, 1, g)

        @test (value(h)) == (1)
        @test (value(j)) == (0)

        push!(g, 2)
        step()
        @test (value(h)) == (1)

        push!(g, 3)
        step()
        @test (value(h)) == (3)

        g = Signal(0)
        pred = x -> x % 2 != 0
        h = filter(pred, g)

        push!(g, 2)
        step()
        @test (value(h)) == (0)

        push!(g, 3)
        step()
        @test (value(h)) == (3)
    end

    @testset "filter counts" begin
        a = Signal(1; name="a")
        b = Signal(2; name="b")
        c = filter(value(a), a; name="c") do aval; aval > 1 end
        d = map(*,b,c)
        count = foldp((x, y) -> x+1, 0, d)
        @test (value(count)) == (0)
        push!(a, 0)
        step()
        @test (value(count)) == (0)
    end

    @testset "sampleon" begin
        # sampleon
        g = Signal(0)
        nv = number()
        push!(g, nv)
        println("step 1")
        step()
        i = Signal(true)
        j = sampleon(i, g)
        # default value
        @test (value(j)) == (value(g)) # j == g == nv)
        push!(g, value(g)-1)
        println("step 2")
        step()
        @test (value(j)) == (value(g)+1) # g is nv - 1, j is unchanged on nv)
        push!(i, true)
        println("step 3")
        step() # resample
        @test (value(j)) == (value(g))
    end

    @testset "droprepeats" begin
        # droprepeats
        count = s -> foldp((x, y) -> x+1, 0, s)

        k = Signal(1)
        l = droprepeats(k)

        @test (value(l)) == (value(k))
        push!(k, 1)
        step()
        @test (value(l)) == (value(k))
        push!(k, 0)
        step()
        #println(l.value, " ", value(k))
        @test (value(l)) == (value(k))

        m = count(k)
        n = count(l)

        seq = [1, 1, 1, 0, 1, 0, 1, 0, 0]
        map(x -> begin push!(k, x); step() end, seq)

        @test (value(m)) == (length(seq))
        @test (value(n)) == (6)
    end

    @testset "filterwhen" begin
        # filterwhen
        b = Signal(false)
        n = Signal(1)
        dw = filterwhen(b, 0, n)
        @test (value(dw)) == (0)
        push!(n, 2)
        step()
        @test (value(dw)) == (0)
        push!(b, true)
        step()
        @test (value(dw)) == (0)
        push!(n, 1)
        step()
        @test (value(dw)) == (1)
        push!(n, 2)
        step()
        @test (value(dw)) == (2)
        dw = filterwhen(b, 0, n)
        @test (value(dw)) == (2)
    end

    @testset "push! inside push!" begin
        a = Signal(0)
        b = Signal(1)
        Reactive.preserve(map(x -> push!(a, x), b))

        @test (value(a)) == (0)

        step()
        @test (value(a)) == (1)

        push!(a, 2)
        step()
        @test (value(a)) == (2)
        @test (value(b)) == (1)

        push!(b, 3)
        step()
        @test (value(b)) == (3)
        @test (value(a)) == (2)

        step()
        @test (value(a)) == (3)
    end

    @testset "previous" begin
        x = Signal(0)
        y = previous(x)
        @test (value(y)) == (0)

        push!(x, 1)
        step()

        @test (value(y)) == (0)

        push!(x, 2)
        step()

        @test (value(y)) == (1)

        push!(x, 3)
        step()

        @test (value(y)) == (2)
        @test (queue_size()) == (0)
    end


    @testset "delay" begin
        x = Signal(0)
        y = delay(x)
        @test (value(y)) == (0)

        push!(x, 1)
        step()

        @test (queue_size()) == (1)
        @test (value(y)) == (0)

        step()
        @test (value(y)) == (1)
        @test (queue_size()) == (0)
    end

    @testset "bind" begin
        x = Signal(0; name="x")
        y = Signal(0; name="y")
        zpre_count = 0
        zpost_count = 0
        zpre = map(yval->(zpre_count+=1; 2yval), y; name="zpre")
        # map(...) runs the function once to get the init value on creation
        @test (zpre_count) == (1)
        bind!(y, x)
        @test (zpre_count) == (2) # initialising the bind should cause zpre to run too)
        zpost = map(yval->(zpost_count+=1; 2yval), y; name="zpost")

        @test (zpre_count) == (2)
        @test (zpost_count) == (1)

        @show queue_size()
        push!(x,1000)
        step()

        @test (value(y)) == (1000)
        @test (value(zpre)) == (2000)
        @test (value(zpost)) == (2000)
        @test (zpre_count) == (3)
        @test (zpost_count) == (2)
        @test (bound_srcs(y)) == ([x])
        @test (bound_dests(x)) == ([y])

        unbind!(y,x)
        push!(x,0)
        step()

        @test (value(y)) == (1000)
        @test (value(zpre)) == (2000)
        @test (value(zpost)) == (2000)

        # bind where dest is before src in node list
        a = Signal(1; name="a")
        b = map(x->2x, a; name="b")
        c = Signal(1; name="c")
        d = map(x->4x, c; name="d")
        bind!(a, d)
        @test (value(d)) == (value(a))

        @test (queue_size()) == (0)

        push!(c, 3)
        @test (queue_size()) == (1)
        step()
        @test (value(c)) == (3)
        @test (value(d)) == (4*3)
        @test (value(a)) == (4*3)
        @test (value(b)) == (2*4*3)

    end

    @testset "bindmap" begin

        src2dst(x) = x + 2
        dst2src(x) = x - 2

        # oneway with initiation
        src = Signal(3)
        dst = Signal(0)
        bindmap!(dst, src2dst, src)
        @test (value(dst)) == (5)
        push!(src, 2)
        step()
        @test (value(dst)) == (4)
        push!(dst, 5)
        step()
        @test (value(src)) == (2)
        unbind!(dst,src)
        push!(src,1)
        step()
        @test (value(dst)) == (5)

        # twoway with initiation
        src = Signal(3)
        dst = Signal(0)
        bindmap!(dst, src2dst, src, dst2src)
        @test (value(dst)) == (5)
        push!(src, 2)
        step()
        @test (value(dst)) == (4)
        push!(dst, 5)
        step()
        @test (value(src)) == (3)
        unbind!(dst,src,false) # test oneway first
        push!(src,1)
        step()
        @test (value(dst)) == (5)
        push!(dst,1)
        step()
        @test (value(src)) == (-1)

        # This should work but I think line 444 in operators.jl shouldn't exit if the twoway unbind! was applied after a oneway unbind!.
        # unbind!(dst,src) # test other way as well
        # push!(dst,2)
        # step()
        # @test (value(src)) == (-1)

        # oneway without initiation
        src = Signal(3)
        dst = Signal(0)
        bindmap!(dst, src2dst, src, initial=false)
        @test (value(dst)) == (0)
        push!(src, 2)
        step()
        @test (value(dst)) == (4)
        push!(dst, 5)
        step()
        @test (value(src)) == (2)
        unbind!(dst,src)
        push!(src,1)
        step()
        @test (value(dst)) == (5)

        # twoway without initiation
        src = Signal(3)
        dst = Signal(0)
        bindmap!(dst, src2dst, src, dst2src, initial=false)
        @test (value(dst)) == (0)
        push!(src, 2)
        step()
        @test (value(dst)) == (4)
        push!(dst, 5)
        step()
        @test (value(src)) == (3)
        unbind!(dst,src)
        push!(src,1)
        step()
        @test (value(dst)) == (5)
        push!(dst,2)
        step()
        @test (value(src)) == (1)

    end

end
