facts("Flatten") do

    a = Signal(0)
    b = Signal(1)

    c = Signal(a)

    d = flatten(c)
    cnt = foldp((x, y) -> x+1, 0, d)

    context("Signal{Signal} -> flat Signal") do
        # Flatten implies:
        @fact value(c) --> a
        @fact value(d) --> value(a)
    end

    context("Initial update count") do
        @fact value(cnt) --> 0
    end

    context("Current signal updates") do
        push!(a, 2)
        step()

        @fact value(cnt) --> 1
        @fact value(d) --> value(a)
    end

    context("Signal swap") do
        push!(c, b)
        step()
        @fact value(cnt) --> 2
        @fact value(d) --> value(b)

        push!(a, 3)
        step()
        @fact value(cnt) --> 2
        @fact value(d) --> value(b)

        push!(b, 3)
        step()

        @fact value(cnt) --> 3
        @fact value(d) --> value(b)
    end

    context("Subtle sig swap issue") do
        # When a node, a map (e) in this case, has a flatten as a parent, but also
        # a signal that is the flatten parent sigsig's (c's) current value ("a" here)
        # then when the sigsig gets pushed another value, you want the map to
        # still update on changes to a, even after the map is "rewired" when a
        # new value is pushed to c.

        a = Signal(1)
        b = Signal(2)
        c = Signal(a)
        d = flatten(c)
        e = map(*, a, d) #e is dependent on "a" directly and through d

        @fact value(e) --> 1
        push!(a, 3)
        step()
        @fact value(a) --> 3
        @fact value(d) --> 3
        @fact value(e) --> 9

        push!(c, b)
        @fact value(e) --> 9 # no change until step
        step()
        @fact value(d) --> 2 # d now takes b's value
        @fact value(e) --> 6 # e == d * a == 2 * 3 == 6

        # the push!(c, b) should have triggered a "rewiring" of the graph
        # so that updates to b affect d and e
        push!(b, 9)
        step()
        @fact value(d) --> 9  # d now takes b's value
        @fact value(e) --> 27 # e == d * a == 9 * 3 == 27

        # changes to a should still affect e (but not d)
        push!(a, 4)
        @fact value(e) --> 27 # no change until step
        step()
        @fact value(a) --> 4
        @fact value(d) --> 9 # no change to d
        @fact value(e) --> 36 # a*d == 4 * 9

        @fact queue_size() --> 0
    end

end
