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
f = reduce(+, a, 0)
nums = int(rand(100)*1000)
map(x -> update(a, x), nums)

@test sum(nums) == f.value
