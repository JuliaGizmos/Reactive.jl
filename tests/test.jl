using Base.Test
using React

## Basics

a = Input(1)
b = Lift{Int}(x -> x*x, a)

update(a, 3)
@test b.value == 9

update(a, -7)
@test b.value == 49

## Multiple inputs to Lift
c = Lift{Int}((x, y) -> x+y, a, b)
@test c.value == 42

update(a, 9)
@test c.value == 90

