
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
