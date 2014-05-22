using Base.Test
using React

number() = int(rand()*1000)

## Basics

a = Input(number())
b = lift(Int, x -> x*x, a)

update(a, number())
@test b.value == a.value*a.value

update(a, -number())
@test b.value == a.value*a.value

## Multiple inputs to Lift
c = lift(Int, +, a, b)
@test c.value == a.value + b.value

update(a, number())
@test c.value == a.value+b.value

## Merge
d = Input(number())
e = merge(d, a, b)

# precedence to d
@test e.value == d.value

update(a, number())
# precedence to a over b
@test e.value == a.value

## reduce over time
update(a, 0)
f = reduce(+, 0, a)
nums = int(rand(100)*1000)
map(x -> update(a, x), nums)

@test sum(nums) == f.value

# dropif
g = Input(0)
pred = x -> x % 2 == 0
h = dropif(pred, 1, g)

@test h.value == 1

update(g, 2)
@test h.value == 1

update(g, 3)
@test h.value == 3

# sampleon

update(g, number())
i = Input(true)
j = sampleon(i, g)
# default value
@test j.value == g.value
update(g, g.value-1)
@test j.value == g.value+1
update(i, true)
@test j.value == g.value

# droprepeats
count = s -> reduce((x, y) -> x+1, 0, s)

k = Input(1)
l = droprepeats(k)

@test l.value == k.value
update(k, 1)
@test l.value == k.value
update(k, 0)
#println(l.value, " ", k.value)
@test l.value == k.value

m = count(k)
n = count(l)

seq = [1, 1, 1, 0, 1, 0, 1, 0, 0]
map(x -> update(k, x), seq)

@test m.value == length(seq) + 1
@test n.value == 7
