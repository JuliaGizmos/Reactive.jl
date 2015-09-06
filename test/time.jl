queue_size() = Reactive.queue_size(Reactive._messages)

facts("Timing functions") do

    context("fpswhen") do
        b = Input(false)
        t = fpswhen(b, 10)
        acc = foldp((x, y) -> x+1, 0, t)
        sleep(0.14)

        @fact queue_size() --> 0
        push!(b, true)

        dt = @elapsed Reactive.run(11) # the first one starts the timer
        push!(b, false)
        Reactive.run(1)

        sleep(0.11) # no more updates
        @fact queue_size() --> 0

        @fact dt --> roughly(1, atol=0.2) # mac OSX needs a lot of tolerence here
        @fact value(acc) --> 10

    end

    context("fps") do
        t = fps(10)
        acc = foldp(push!, Float64[], t)
        Reactive.run(11) # Starts with 0
        log = copy(value(acc))

        @fact log[1] --> roughly(0.1, atol=0.1) # First one's always crappy
        log = log[2:end]

        @fact sum(log) --> roughly(1.0, atol=0.05)
        @fact [1/10 for i=1:10] --> roughly(log, atol=0.03)

        @fact queue_size() --> 0
        sleep(0.11)
        @fact queue_size() --> 1
        sleep(0.22)
        @fact queue_size() --> 1

        close(acc)
        close(t)

        Reactive.run_till_now()
    end

    context("every") do
        t = every(0.1)
        acc = foldp(push!, Float64[], t)
        Reactive.run(11)
        end_t = time()
        log = copy(value(acc))

        @fact log[end-1] --> roughly(end_t, atol=0.001)

        close(acc)
        close(t)
        Reactive.run_till_now()

        @fact [0.1 for i=1:10] --> roughly(diff(log), atol=0.03)

        sleep(0.2)
        # make sure close actually also closed the timer
        @fact queue_size() --> 0
    end

    context("throttle") do
        x = Input(0)
        y = throttle(0.1, x)
        y′ = throttle(0.2, x, push!, Int[], x->Int[]) # collect intermediate updates
        z = foldp((acc, x) -> acc+1, 0, y)
        z′ = foldp((acc, x) -> acc+1, 0, y)

        push!(x, 1)
        step()

        push!(x, 2)
        step()

        push!(x, 3)
        t0=time()
        step()

        @fact value(y) --> 0
        @fact value(z) --> 0
        @fact value(z′) --> 0
        @fact queue_size() --> 0

        sleep(0.07)

        @fact value(y) --> 0 # update hasn't come in yet
        @fact value(z′) --> 0
        @fact queue_size() --> 0
        sleep(0.1)
        @fact queue_size() --> 1
        step()
        @fact value(y) --> 3
        @fact value(z) --> 1
        sleep(0.1)

        @fact queue_size() --> 1
        step()
        @fact value(z′) --> 1
        @fact value(y′) --> Int[1,2,3]

        push!(x, 3)
        step()

        push!(x, 2)
        step()

        push!(x, 1)
        step()
        sleep(0.2)

        @fact queue_size() --> 2
        step()
        step()
        @fact value(y) --> 1
        @fact value(z′) --> 2
        @fact value(y′) --> Int[3,2,1]
    end
end

