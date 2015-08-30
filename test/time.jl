
facts("Timing functions") do
    context("fps") do
        t = fps(10)
        acc = foldp(push!, Float64[], t)
        Reactive.run(10) # Starts with 0
        log = copy(value(acc))

        @fact sum(log) --> roughly(1.0, atol=0.05)
        @fact [1/10 for i=1:10] --> roughly(log, atol=0.03)

        @fact Reactive.queue_size(Reactive._messages) --> 0
        sleep(0.11)
        @fact Reactive.queue_size(Reactive._messages) --> 1
        sleep(0.22)
        @fact Reactive.queue_size(Reactive._messages) --> 1

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
        if VERSION >= v"0.4.0-dev"
            @fact Reactive.queue_size(Reactive._messages) --> 0
        else
            warn("every will not stop the timer on julia 0.3")
        end
    end
end

