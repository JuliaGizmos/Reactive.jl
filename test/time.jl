@testset "Timing functions" begin

    @testset "fpswhen" begin
        b = Signal(false)
        t = fpswhen(b, 2)
        acc = foldp((x, y) -> x+1, 0, t)
        sleep(0.75)

        @test (queue_size()) == (0)
        push!(b, true)

        step() # processing the push to b will start the fpswhen's timer
        # then we fetch for two pushes from the timer, which should take ~ 1sec
        dt = @elapsed Reactive.run(2)
        push!(b, false)
        Reactive.run(1) # setting b to false should stop the timer

        sleep(0.75) # no more updates
        @test (queue_size()) == (0)

        @show dt
        @test isapprox(dt, 1, atol = 0.3) # mac OSX needs a lot of tolerence here)
        @test (value(acc)) == (2)

    end

    @testset "every" begin
        num_steps = 4
        dt = 0.5
        # gets pushed the `time()` every `dt` seconds
        t = every(dt)

        # append the `time()` to the Float64[] array, once every dt secs
        acc = foldp(push!, Float64[], t)

        # process num_steps pushes (should take num_steps*dt secs)
        Reactive.run(num_steps)
        end_t = time() # should be equal to the last time in acc
        # close(t) to avoid `acc` getting pushed to again
        close(t)

        accval = value(acc)
        @show end_t end_t .- accval
        @test isapprox(accval[end], end_t, atol=0.01)

        Reactive.run_till_now()

        @test isapprox([0.5, 0.5, 0.5], diff(accval), atol=0.1)

        sleep(0.75)
        # make sure the `close(t)` above actually also closed the timer
        @test (queue_size()) == (0)
    end

    @testset "throttle" begin
        GC.gc()
        x = Signal(0; name="x")
        ydt = 0.5
        y′dt = 1.1
        y = throttle(ydt, x; name="y", leading=false)
        y′ = throttle(y′dt, x, push!, Int[], x->Int[]; name="y′", leading=false) # collect intermediate updates
        z = foldp((acc, x) -> begin
            println("z got ", x)
            acc+1
        end, 0, y)
        z′ = foldp((acc, x) -> begin
            println("z′ got ", x)
            acc+1
        end, 0, y′)
        y′prev = previous(y′)

        i = 0
        sleep_time = 0.15
        t0 = typemax(Float64)
        # push and sleep for a bit, y and y′ should only update every ydt and
        # y′dt seconds respectively
        while time() - t0 <= 2.2
            i += 1
            push!(x, i)

            Reactive.run_till_now()
            t0 == typemax(Float64) && (t0 = time()) # start timer here to match signals
            sleep(sleep_time)
        end
        dt = time() - t0
        sleep(max(ydt,y′dt) + 0.1) # sleep for the trailing-edge pushes of the throttles
        Reactive.run_till_now()

        zcount = ceil(dt / ydt) # throttle should have pushed every ydt seconds
        z′count = ceil(dt / y′dt) # throttle should have pushed every y′dt seconds

        @show i dt ydt y′dt zcount z′count value(y) value(y′) value(z) value(z′)

        @test (value(y)) == (i)
        @test isapprox(value(z), zcount, atol=1)
        @test (value(y′)) == ([y′prev.value[end]+1 : i;])
        @test (length(value(y′))) < ((i/(z′count-1)))
        @test isapprox(value(z′), z′count, atol=1)

        # type safety
        s1 = Signal(3)
        s2 = Signal(rand(2,2))
        m = merge(s1, s2)
        t = throttle(1/5, m; typ=Any)
        r = rand(3,3)
        push!(s2, r)
        Reactive.run(1)
        sleep(0.5)
        # Reactive.run(1)
        Reactive.run_till_now()
        @test (value(t)) == (r)
    end

    @testset "debounce" begin
        x = Signal(0)
        y = debounce(0.5, x)
        y′ = debounce(1, x, push!, Int[], x->Int[]) # collect intermediate updates
        z = foldp((acc, x) -> acc+1, 0, y)
        z′ = foldp((acc, x) -> acc+1, 0, y′)

        push!(x, 1)
        step()

        push!(x, 2)
        step()

        push!(x, 3)
        t0=time()
        step()

        @test (value(y)) == (0)
        @test (value(z)) == (0)
        @test (queue_size()) == (0)

        sleep(0.55)

        @test (queue_size()) == (1) # y should have been pushed to by now)
        step() # run the push to y
        @test (value(y)) == (3)
        @test (value(z)) == (1)
        @test (value(z′)) == (0)
        sleep(0.5)

        @test (queue_size()) == (1) # y′ should have pushed by now)
        step() # run the push to y′
        @test (value(z′)) == (1)
        @test (value(y′)) == (Int[1,2,3])

        push!(x, 3)
        step()

        push!(x, 2)
        step()

        push!(x, 1)
        step()
        sleep(1.1)

        @test (queue_size()) == (2) #both y and y′ should have pushed)
        step()
        step()
        @test (value(y)) == (1)
        @test (value(z′)) == (2)
        @test (value(y′)) == (Int[3,2,1])

        # type safety
        s1 = Signal(3)
        s2 = Signal(rand(2,2))
        m = merge(s1, s2)
        t = debounce(1/5, m; typ=Any)
        r = rand(3,3)
        push!(s2, r)
        Reactive.run(1)
        sleep(0.5)
        Reactive.run(1)
        @test (value(t)) == (r)
    end
end
