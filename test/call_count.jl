
if !isdefined(:number)
    number() = rand(0:100)
end

facts("Call counting") do
    a = Signal(0)
    b = Signal(0)

    c = map(+, a, b)
    d = merge(a, b)
    e = map(+, a, map(x->2x, a)) # Both depend on a
    f = map(+, a, b, c, e)

    count = s -> foldp((x, y) -> x+1, 0, s)

    ca = count(a)
    cb = count(b)
    cc = count(c)
    cd = count(d)
    ce = count(e)
    cf = count(f)

    for i in 1:100
        push!(a, number())
        step()
        push!(b, number())
        step()

        @fact ca.value --> i
        @fact cb.value --> i
        @fact cc.value --> 2i
        @fact cd.value --> 2i
        @fact ce.value --> i
        @fact cf.value --> 2i
    end
end

facts("multi-path graphs") do
    a = Signal(0)
    b = Signal(0)

    c = map(+, a, b)
    d = merge(a, b)
    e = map(+, a, map(x->2x, a)) # Both depend on a
    f = map(+, a, b, c, e)

    for (av,bv) in [(1,2),(1,3),(7,7)]
        push!(a, av)
        push!(b, bv-1)
        Reactive.run_till_now()
        push!(b, bv)
        Reactive.run_till_now()
        @fact value(c) --> av + bv
        @fact value(e) --> 3av
        @fact value(d) --> bv
        @fact value(f) --> 5av + 2bv
    end

    xv = 2
    x = Signal(xv)
    y = map(identity, x)
    x2 = map(x->2x, x)
    z = map(+, y, x2)
    Reactive.run_till_now()
    @fact value(y) --> xv
    @fact value(x2) --> 2xv
    @fact value(z) --> 3xv

    xv2 = xv + 1
    push!(x, xv2)
    Reactive.run_till_now()
    @fact value(z) --> 3xv2
end
