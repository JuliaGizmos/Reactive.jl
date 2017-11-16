Reactive.__init__()
import Reactive: runner_task

facts("Queue runner") do
    context("Queue restarts during push!") do
        @fact queue_size() --> 0
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
            wait(Reactive.runner_task[])
            @fact queue_size() --> 0
            @fact orig_runner --> not(Reactive.runner_task[]) # we should have a new queue runner
            @fact bcount --> expected_bcount
        end
        @fact bcount --> 0
        test_queue(1, Reactive.runner_task[])
        test_queue(2, Reactive.runner_task[])
    end

    context("Multiple queue restarts during a single action") do
        @fact queue_size() --> 0
        bcount = 0
        a = Signal(1)
        foreach(a; init=nothing) do _
            b = Signal(1)
            bcount += 1
            foreach(b; init=nothing) do _
                bcount += 1 #won't get run because of the init=nothing
            end
            foreach(b; init=nothing) do _
                bcount += 1 #won't get run because of the init=nothing
            end
            nothing
        end
        function test_queue(expected_bcount, orig_runner)
            push!(a, 3)
            wait(Reactive.runner_task[])
            @fact queue_size() --> 0
            @fact orig_runner --> not(Reactive.runner_task[]) # we should have a new queue runner
            @fact bcount --> expected_bcount
        end
        @fact bcount --> 0
        test_queue(1, Reactive.runner_task[])
        test_queue(2, Reactive.runner_task[])
    end

    context("Queue restarts after more than one push!") do
        @fact queue_size() --> 0
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
            push!(a, 4)
            wait(Reactive.runner_task[])
            @fact queue_size() --> 0
            @fact orig_runner --> not(Reactive.runner_task[]) # we should have a new queue runner
            @fact bcount --> expected_bcount*2
        end
        @fact bcount --> 0
        test_queue(1, Reactive.runner_task[])
        test_queue(2, Reactive.runner_task[])
    end
end


if !istaskdone(Reactive.runner_task[])
    Reactive.stop()
    wait(Reactive.runner_task[])
end
