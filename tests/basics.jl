using Base.Test
using React

number() = int(rand()*1000)

## Basics

a = Input(number())
b = lift(x -> x*x, a)

# Lift type
@test isa(b, React.Lift{Int})

# type conversion
push!(a, 1.0)
@test b.value == 1
@test_throws InexactError push!(a, 1.1) # inexact error

push!(a, number())
@test b.value == a.value*a.value

push!(a, -number())
@test b.value == a.value*a.value

## Multiple inputs to Lift
c = lift(+, Int, a, b)
@test c.value == a.value + b.value

push!(a, number())
@test c.value == a.value+b.value

## Merge
d = Input(number())
e = merge(d, b, a)

# precedence to d
@test e.value == d.value

push!(a, number())
# precedence to b over a
@test e.value == b.value

## foldl over time
push!(a, 0)
f = foldl(+, 0, a)
nums = int(rand(100)*1000)
map(x -> push!(a, x), nums)

@test sum(nums) == f.value

# filter
g = Input(0)
pred = x -> x % 2 != 0
h = filter(pred, 1, g)

@test h.value == 1

push!(g, 2)
@test h.value == 1

push!(g, 3)
@test h.value == 3

# sampleon

push!(g, number())
i = Input(true)
j = sampleon(i, g)
# default value
@test j.value == g.value
push!(g, g.value-1)
@test j.value == g.value+1
push!(i, true)
@test j.value == g.value

# droprepeats
count = s -> foldl((x, y) -> x+1, 0, s)

k = Input(1)
l = droprepeats(k)

@test l.value == k.value
push!(k, 1)
@test l.value == k.value
push!(k, 0)
#println(l.value, " ", k.value)
@test l.value == k.value

m = count(k)
n = count(l)

seq = [1, 1, 1, 0, 1, 0, 1, 0, 0]
map(x -> push!(k, x), seq)

@test m.value == length(seq) + 1
@test n.value == 7

# dropwhen
b = Input(true)
n = Input(1)
dw = dropwhen(b, 0, n)
@test dw.value == 0
push!(n, 2)
@test dw.value == 0
push!(b, false)
@test dw.value == 0
push!(n, 1)
@test dw.value == 1
push!(n, 2)
@test dw.value == 2
dw = dropwhen(b, 0, n)
@test dw.value == 2
