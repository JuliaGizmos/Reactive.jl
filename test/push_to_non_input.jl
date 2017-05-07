using Reactive

function standard_push_test(non_input::Signal)
    m = map(x->2x, non_input)
    pval = number()
    push!(non_input, pval)
    step()

    @fact value(non_input) --> pval
    @fact value(m) --> 2pval
end

facts("Push to non-input nodes") do

    a = Signal(number(); name="a")
    b = map(x -> x*x, a; name="b")

    context("push to map") do
        m = map(x->2x, b)

        push!(b, 10.0)
        step()
        @fact value(b) --> 10.0
        @fact value(m) --> 2value(b)

        push!(a, 2.0)
        step()
        @fact value(b) --> 4.0
        @fact value(m) --> 2value(b)

        push!(b, 3.0)
        step()
        @fact value(b) --> 3.0
        @fact value(m) --> 2value(b)
    end


    context("push to merge") do
        ## Merge
        d = Signal(number(); name="d")
        e = merge(b, d, a; name="e")
        m = map(x->2x, e)
        # precedence to d
        @fact value(e) --> value(d)
        @fact value(m) --> 2value(e)

        standard_push_test(e)
    end

    context("push to foldp") do
        gc()
        f = foldp(+, 0, a)
        m = map(x->2x, f)

        standard_push_test(f)
    end

    context("push to filter") do
        g = Signal(0)
        pred = x -> x % 2 != 0
        h = filter(pred, 1, g)
        standard_push_test(h)
    end

    context("push to sampleon") do
        # sampleon
        g = Signal(0)
        nv = number()
        push!(g, nv)
        step()
        i = Signal(true)
        j = sampleon(i, g)
        standard_push_test(j)
    end

    context("push to droprepeats") do
        # droprepeats
        k = Signal(1)
        l = droprepeats(k)

        standard_push_test(l)
    end

    context("push to filterwhen") do
        # filterwhen
        b = Signal(false)
        n = Signal(1)
        dw = filterwhen(b, 0, n)
        standard_push_test(dw)
    end

    context("push to previous") do
        x = Signal(0)
        y = previous(x)
        standard_push_test(y)
    end

    context("push to delay") do
        x = Signal(0)
        y = delay(x)
        standard_push_test(y)
    end

    context("bind non-input") do
        s = Signal(1; name="sig 1")
        m = map(x->2x, s; name="m")
        s2 = Signal(3; name="sig 2")
        push!(m, 10)
        step()
        @fact value(m) --> 10

        bind!(m, s2) #two-way bind
        @fact value(m) --> 3
        @fact value(s2) --> 3

        push!(m, 6)
        step()
        @fact value(m) --> 6
        @fact value(s2) --> 6

        push!(s2, 10)
        step()
        @fact value(m) --> 10
        @fact value(s2) --> 10
    end

end
