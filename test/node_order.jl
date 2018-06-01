@testset "multi-path graphs 1" begin
    a = Signal(0)
    b = Signal(0)

    c = map(+, a, b)
    d = merge(a, b)
    e = map(+, a, map(x->2x, a)) # Both depend on a
    f = map(+, a, b, c, e)

    @test (queue_size()) == (0)

    for (av,bv) in [(1,2),(1,3),(7,7)]
        @show av bv
        push!(a, av)
        push!(b, bv-1)
        Reactive.run_till_now()
        push!(b, bv)
        Reactive.run_till_now()
        @test (value(c)) == (av + bv)
        @test (value(e)) == (3av)
        @test (value(d)) == (bv)
        @test (value(f)) == (5av + 2bv)
    end

    xv = 2
    x = Signal(xv)
    y = map(identity, x)
    x2 = map(x->2x, x)
    z = map(+, y, x2)
    Reactive.run_till_now()
    @test (value(y)) == (xv)
    @test (value(x2)) == (2xv)
    @test (value(z)) == (3xv)

    xv2 = xv + 1
    push!(x, xv2)
    Reactive.run_till_now()
    @test (value(z)) == (3xv2)
end

@testset "multi-path graphs 2" begin
    a = Signal(0)
    b = Signal(0)

    c = map(+, a, b)
    d = merge(a, b)
    e = map(+, a, map(x->2x, a)) # Both depend on a
    f = map(+, a, b, c, e)

    for (av,bv) in [(1,2),(1,3),(7,7)]
        push!(a, av)
        push!(b, bv-1)
        Reactive.run_till_now()
        push!(b, bv)
        Reactive.run_till_now()
        @test (value(c)) == (av + bv)
        @test (value(e)) == (3av)
        @test (value(d)) == (bv)
        @test (value(f)) == (5av + 2bv)
    end

    xv = 2
    x = Signal(xv)
    y = map(identity, x)
    x2 = map(x->2x, x)
    z = map(+, y, x2)
    Reactive.run_till_now()
    @test (value(y)) == (xv)
    @test (value(x2)) == (2xv)
    @test (value(z)) == (3xv)

    xv2 = xv + 1
    push!(x, xv2)
    Reactive.run_till_now()
    @test (value(z)) == (3xv2)
end

@testset "multi-path graphs: dfs good, bfs bad" begin
    # DFS good, BFS bad
    # s4x is initially 8 (4*2), after push!(sx,3), s4x should be 12 (4*3), but is instead 9.
    # initially: sx is 2, s2x is 4, s3x is 6, s4x is 8
    # after push!(sx, 3), what happens is:
    # BFS
        # order: sx, s2x, s4x, s3x (bad)
        # sx is updated to 3, s2x updates correctly (to 6), but then s4x is next in the queue,
        # and sees s3x's old value of 6, adds it to sx (3), and gets 9. Finally s3x updates
        # correctly to 9, but it's all too late
    # DFS
        # order: sx, s2x, s3x, s4x (good)
    xv = 2
    sx = Signal(xv; name="sx")
    s2x = map(x->2x, sx; name="s2x")
    s3x = map(x->x + x÷2, s2x; name="s3x")
    s4x = map(+, sx, s3x; name="s4x")
    @test (value.([sx, s2x, s3x, s4x])) == ([2, 4, 6, 8])
    push!(sx, 3)
    Reactive.run_till_now()
    @test (value.([sx, s2x, s3x, s4x])) == ([3, 6, 9, 12])
end

@testset "multi-path graphs: bfs good, dfs bad" begin
    #BFS good, DFS bad
    # s3x is initially 6 (3*2), after push!(sx, 3), s3x should be 9 (3*3), but is instead 7.
    # initially: sx and s1x1, s1x2 are 2, s2x is 4, s3x is 6
    # after push!(sx, 3), what happens is:
    # DFS:
        # order sx, s1x1, s3x, s1x2 (bad)
        # sx is updated to 3, s1x1 updates correctly (to 3), but then s3x is next in the queue,
        # and sees s1x2's old value of 2, adds it to sx (3), s1x1(3) and gets 8. Finally s1x2 updates
        # correctly to 3, but it's all too late
    # BFS:
        # order sx, s1x1, s1x2, sx3 (good)
    xv = 2
    sx = Signal(xv)
    s1x1 = map(identity, sx)
    s1x2 = map(identity, sx)
    s3x = map(+, s1x1, s1x2, sx)
    @test (value.([sx, s1x1, s1x2, s3x])) == ([2, 2, 2, 6])
    push!(sx, 3)
    Reactive.run_till_now()
    @test (value.([sx, s1x1, s1x2, s3x])) == ([3, 3, 3, 9])
end

@testset "multi-path graphs: dfs bad, bfs bad" begin
    #BFS bad, dfs bad
    # s3x is initially 6 (3*2), after push!(sx, 3), s3x should be 9 (3*3), but is instead 7.
    # what happens in BFS is:
    # initially: sx and s1x1, s1x2 are 2, s2x is 4, s3x is 6
    # after push!(sx, 3)
    # BFS:
        # order is x, s1x1, s1x2, s3x, s2x (bad)
        # correct: x, s1x1, s1x2, s2x, s3x)
        # sx is updated to 3, s1x1 and s1x2 update correctly (to 3), but s3x is next in the queue,
        # and sees s2x's old value of 4, adds it to sx (3), and gets 7. Finally s2x updates
        # correctly to 6 (2*3), but it's all too late
    # DFS:
        # order is x, s1x1, s2x, s3x, s1x2 (bad)
        # correct: x, s1x1, s1x2, s2x, s3x)
        # sx is updated to 3, s1x1 updates correctly to 3, but then:
        # s2x sees s1x2 as 2 and updates to 5 (3 + 2) - but should be 6, then
        # s3x sees s2x as 5, adds sx (3) and gets 8
        # s1x2 then updates to 3, but that's it, s2x is 5 (not 6), s3x is 8 (not 9)

    xv = 2
    sx = Signal(xv)
    s1x1 = map(identity, sx)
    s1x2 = map(identity, sx)
    s2x = map(+, s1x1, s1x2)
    s3x = map(+, sx, s2x)
    @test (value.([sx, s1x1, s1x2, s2x, s3x])) == ([2, 2, 2, 4, 6])
    push!(sx, 3)
    Reactive.run_till_now()
    @test (value.([sx, s1x1, s1x2, s2x, s3x])) == ([3, 3, 3, 6, 9])
end
