using Base.Test
using Reactive

facts("Flatten") do

    a = Input(0)
    b = Input(1)

    c = Input(a)

    d = flatten(c)
    cnt = foldl((x, y) -> x+1, 0, d)

    context("Signal{Signal} -> flat Signal") do
        # Flatten implies:
        @fact value(c) => a
        @fact value(d) => value(a)
    end

    context("Initial update count") do

        @fact value(cnt) => 0
    end

    context("Current signal updates") do
        push!(a, 2)

        @fact value(cnt) => 1
        @fact value(d) => value(a)
    end

    context("Signal swap") do
        push!(c, b)
        @fact value(cnt) => 2
        @fact value(d) => value(b)

        push!(a, 3)
        @fact value(cnt) => 2
        @fact value(d) => value(b)

        push!(b, 3)

        @fact value(cnt) => 3
        @fact value(d) => value(b)
    end
end
