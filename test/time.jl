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

        @fact dt --> roughly(1, atol=0.1)
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
end

