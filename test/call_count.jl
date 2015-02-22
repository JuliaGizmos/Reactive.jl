using FactCheck
using Reactive

number() = int(rand()*100)

facts("Call counting") do
    a = Input(0)
    b = Input(0)

    c = lift(+, Int, a, b)
    d = merge(a, b)
    e = lift(+, Int, a, lift(x->2x, Int, a)) # Both depend on a
    f = lift(+, Int, a, b, c, e)

    count = s -> foldl((x, y) -> x+1, 0, s)

    ca = count(a)
    cb = count(b)
    cc = count(c)
    cd = count(d)
    ce = count(e)
    cf = count(f)

    for i in 1:100
        push!(a, number())
        push!(b, number())

        @fact ca.value => i
        @fact cb.value => i
        @fact cc.value => 2i
        @fact cd.value => 2i
        @fact ce.value => i
        @fact cf.value => 2i
    end
end
