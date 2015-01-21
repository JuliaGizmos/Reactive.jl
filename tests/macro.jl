x = Input(1)

# basic lift macro
y = @lift x^2

@test x.value^2 == y.value

push!(x, 2)

@test x.value^2 == y.value

t1 = @lift (x,)
t2 = @lift (x, y)
l1 = @lift [x]
l2 = @lift [x, y^2]
c1 = @lift {x}

push!(x, 3)

@test t1.value == (x.value,)
@test t2.value == (x.value, y.value)
@test l1.value == [x.value]
@test l2.value == [x.value, y.value^2]
@test c1.value ==  {x.value}

# test use in a function
k = 3
f(x,y) = @lift x + y + 1 + k

z = f(x,y)
push!(x, 3)
@test x.value^2 + x.value + 4 == z.value

