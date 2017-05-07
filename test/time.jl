facts("Timing functions") do

    context("fpswhen") do
        b = Signal(false)
        t = fpswhen(b, 2)
        acc = foldp((x, y) -> x+1, 0, t)
        sleep(0.75)

        @fact queue_size() --> 0
        push!(b, true)

        step() # processing the push to b will start the fpswhen's timer
        # then we wait for two pushes from the timer, which should take ~ 1sec
        dt = @elapsed Reactive.run(2)
        push!(b, false)
        Reactive.run(1) # setting b to false should stop the timer

        sleep(0.75) # no more updates
        @fact queue_size() --> 0

        @show dt
        @fact dt --> roughly(1, atol=0.25) # mac OSX needs a lot of tolerence here
        @fact value(acc) --> 2

    end

    context("every") do
        t = every(0.5)
        acc = foldp(push!, Float64[], t)
        Reactive.run(4)
        end_t = time()
        log = copy(value(acc))

        @fact log[end-1] --> roughly(end_t, atol=0.01)

        close(acc)
        close(t)
        Reactive.run_till_now()

        @fact [0.5, 0.5, 0.5] --> roughly(diff(log), atol=0.1)

        sleep(0.75)
        # make sure close actually also closed the timer
        @fact queue_size() --> 0
    end

    context("throttle") do
        gc()
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

        @fact value(y) --> i
        @fact value(z) --> roughly(zcount, atol=1)
        @fact value(y′) --> [y′prev.value[end]+1 : i;]
        @fact length(value(y′)) --> less_than(i/(z′count-1))
        @fact value(z′) --> roughly(z′count, atol=1)

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
        @fact value(t) --> r
    end

    context("debounce") do
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

        @fact value(y) --> 0
        @fact value(z) --> 0
        @fact queue_size() --> 0

        sleep(0.55)

        @fact queue_size() --> 1 # y should have been pushed to by now
        step() # run the push to y
        @fact value(y) --> 3
        @fact value(z) --> 1
        @fact value(z′) --> 0
        sleep(0.5)

        @fact queue_size() --> 1 # y′ should have pushed by now
        step() # run the push to y′
        @fact value(z′) --> 1
        @fact value(y′) --> Int[1,2,3]

        push!(x, 3)
        step()

        push!(x, 2)
        step()

        push!(x, 1)
        step()
        sleep(1.1)

        @fact queue_size() --> 2 #both y and y′ should have pushed
        step()
        step()
        @fact value(y) --> 1
        @fact value(z′) --> 2
        @fact value(y′) --> Int[3,2,1]

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
        @fact value(t) --> r
    end
end
