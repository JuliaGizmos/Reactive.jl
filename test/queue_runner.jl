Reactive.__init__()

facts("Queue runner") do
    @fact queue_size() --> 0
    context("Queue restarts during push!") do
        bcount = 0
        a = Signal(1)
        foreach(a; init=nothing) do _
            b = Signal(1)
            bcount += 1
            foreach(b; init=nothing) do _
                bcount += 1 #won't get run because of the init=nothing
            end
            nothing
        end
        function test_queue(expected_bcount, orig_runner)
            push!(a, 3)
            wait(Reactive.runner_task)
            @fact queue_size() --> 0 # stop message is in the queue
            @fact orig_runner --> not(Reactive.runner_task) # we should have a new queue runner
            @fact bcount --> expected_bcount
        end
        @fact bcount --> 0
        test_queue(1, Reactive.runner_task)
        test_queue(2, Reactive.runner_task)
    end
end


if !istaskdone(Reactive.runner_task)
    Reactive.stop()
    wait(Reactive.runner_task)
end
