using Reactive

function standard_push_test(non_input::Signal)
    m = map(x->2x, non_input)
    pval = number()
    push!(non_input, pval)
    step()

    @test (value(non_input)) == (pval)
    @test (value(m)) == (2pval)
end

@testset "Push to non-input nodes" begin

    a = Signal(number(); name="a")
    b = map(x -> x*x, a; name="b")

    @testset "push to map" begin
        m = map(x->2x, b)

        push!(b, 10.0)
        step()
        @test (value(b)) == (10.0)
        @test (value(m)) == (2value(b))

        push!(a, 2.0)
        step()
        @test (value(b)) == (4.0)
        @test (value(m)) == (2value(b))

        push!(b, 3.0)
        step()
        @test (value(b)) == (3.0)
        @test (value(m)) == (2value(b))
    end


    @testset "push to merge" begin
        ## Merge
        d = Signal(number(); name="d")
        e = merge(b, d, a; name="e")
        m = map(x->2x, e)
        # precedence to d
        @test (value(e)) == (value(d))
        @test (value(m)) == (2value(e))

        standard_push_test(e)
    end

    @testset "push to foldp" begin
        GC.gc()
        x = Signal(number())
        f = foldp(+, 0, x)

        standard_push_test(f)

        # Check for correct continuation
        pval = value(f)
        sval = number()
        push!(x, sval)
        step()

        @test (value(f)) == (pval + sval)
    end

    @testset "push to filter" begin
        g = Signal(0)
        pred = x -> x % 2 != 0
        h = filter(pred, 1, g)
        standard_push_test(h)
    end

    @testset "push to sampleon" begin
        # sampleon
        g = Signal(0)
        nv = number()
        push!(g, nv)
        step()
        i = Signal(true)
        j = sampleon(i, g)
        standard_push_test(j)
    end

    @testset "push to droprepeats" begin
        # droprepeats
        k = Signal(1)
        l = droprepeats(k)

        standard_push_test(l)
    end

    @testset "push to filterwhen" begin
        # filterwhen
        b = Signal(false)
        n = Signal(1)
        dw = filterwhen(b, 0, n)
        standard_push_test(dw)
    end

    @testset "push to previous" begin
        x = Signal(0)
        y = previous(x)
        standard_push_test(y)
    end

    @testset "push to delay" begin
        x = Signal(0)
        y = delay(x)
        standard_push_test(y)
    end

    @testset "bind non-input" begin
        s = Signal(1; name="sig 1")
        m = map(x->2x, s; name="m")
        s2 = Signal(3; name="sig 2")
        push!(m, 10)
        step()
        @test (value(m)) == (10)

        bind!(m, s2) #two-way bind
        @test (value(m)) == (3)
        @test (value(s2)) == (3)

        push!(m, 6)
        step()
        @test (value(m)) == (6)
        @test (value(s2)) == (6)

        push!(s2, 10)
        step()
        @test (value(m)) == (10)
        @test (value(s2)) == (10)
    end

end
