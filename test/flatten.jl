@testset "Flatten" begin

    a = Signal(0)
    b = Signal(1)

    c = Signal(a)

    d = flatten(c)
    cnt = foldp((x, y) -> x+1, 0, d)

    @testset "Signal{Signal} -> flat Signal" begin
        # Flatten implies:
        @test (value(c)) == (a)
        @test (value(d)) == (value(a))
    end

    @testset "Initial update count" begin
        @test (value(cnt)) == (0)
    end

    @testset "Current signal updates" begin
        push!(a, 2)
        step()

        @test (value(cnt)) == (1)
        @test (value(d)) == (value(a))
    end

    @testset "Signal swap" begin
        push!(c, b)
        step()
        @test (value(cnt)) == (2)
        @test (value(d)) == (value(b))

        push!(a, 3)
        step()
        @test (value(cnt)) == (2)
        @test (value(d)) == (value(b))

        push!(b, 3)
        step()

        @test (value(cnt)) == (3)
        @test (value(d)) == (value(b))
    end

    @testset "Subtle sig swap issue" begin
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

        @test (value(e)) == (1)
        push!(a, 3)
        step()
        @test (value(a)) == (3)
        @test (value(d)) == (3)
        @test (value(e)) == (9)

        push!(c, b)
        @test (value(e)) == (9) # no change until step)
        step()
        @test (value(d)) == (2) # d now takes b's value)
        @test (value(e)) == (6) # e == d * a == 2 * 3 == 6)

        # the push!(c, b) should have triggered a "rewiring" of the graph
        # so that updates to b affect d and e
        push!(b, 9)
        step()
        @test (value(d)) == (9)  # d now takes b's value)
        @test (value(e)) == (27) # e == d * a == 9 * 3 == 27)

        # changes to a should still affect e (but not d)
        push!(a, 4)
        @test (value(e)) == (27) # no change until step)
        step()
        @test (value(a)) == (4)
        @test (value(d)) == (9) # no change to d)
        @test (value(e)) == (36) # a*d == 4 * 9)

        @test (queue_size()) == (0)
    end

    @testset "Sigsig's value created after SigSig" begin
        # This is why we need bind! in flatten implementation rather than just
        # setting the flatten's parents to (input, current_node) every time
        # input updates. That won't work if the current_node was created after
        # the flatten (e.g. in the below after pushing a new value to `a`),
        # because updates to the current_node happen further down the `nodes`
        # list than the flatten, so the flatten doesn't get updated.
        a = Signal(number())
        local b
        c = foreach(a) do av
                b = Signal(av)
                foreach(identity, b)
            end
        d = flatten(c)
        b_orig = b

        @test (d.value) == (a.value)

        push!(b, number())
        step()
        @test (d.value) == (b.value)

        push!(a, number())
        step()
        @test (d.value) == (a.value)
        @test (b_orig) != b

        push!(b, number())
        step()
        @test (d.value + 1) == (b.value + 1)
    end
end
