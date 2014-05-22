using Base.Test
using React

number() = int(rand()*100)

a = Input(0)
b = Input(0)

c = lift(Int, +, a, b)
d = merge(a, b)
e = lift(Int, +, a, lift(Int, x->2x, a)) # Both depend on a
f = lift(Int, +, a, b, c, e)

count = s -> reduce((x, y) -> x+1, 0, s)

ca = count(a)
cb = count(b)
cc = count(c)
cd = count(d)
ce = count(e)
cf = count(f)

for i in 1:100
    update(a, number())
    update(b, number())

    @test ca.value == i+1
    @test cb.value == i+1
    @test cc.value == 2i+1
    @test cd.value == 2i+1
    @test ce.value == i+1
    @test cf.value == 2i+1
end
