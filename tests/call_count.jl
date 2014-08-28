using Base.Test
using Reactive

number() = int(rand()*100)

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

    @test ca.value == i
    @test cb.value == i
    @test cc.value == 2i
    @test cd.value == 2i
    @test ce.value == i
    @test cf.value == 2i
end
