Reactive.__init__()
import Reactive: runner_task

@testset "Queue runner" begin
    @testset "Queue restarts during push!" begin
        @test (queue_size()) == (0)
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
            fetch(Reactive.runner_task[])
            @test (queue_size()) == (0)
            @test (orig_runner) != (Reactive.runner_task[]) # we should have a new queue runner)
            @test (bcount) == (expected_bcount)
        end
        @test (bcount) == (0)
        test_queue(1, Reactive.runner_task[])
        test_queue(2, Reactive.runner_task[])
    end

    @testset "Multiple queue restarts during a single action" begin
        @test (queue_size()) == (0)
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
            fetch(Reactive.runner_task[])
            @test (queue_size()) == (0)
            @test (orig_runner) != Reactive.runner_task[] # we should have a new queue runner)
            @test (bcount) == (expected_bcount)
        end
        @test (bcount) == (0)
        test_queue(1, Reactive.runner_task[])
        test_queue(2, Reactive.runner_task[])
    end

    @testset "Queue restarts after more than one push!" begin
        @test (queue_size()) == (0)
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
            fetch(Reactive.runner_task[])
            @test (queue_size()) == (0)
            @test (orig_runner) != (Reactive.runner_task[]) # we should have a new queue runner)
            @test (bcount) == (expected_bcount*2)
        end
        @test (bcount) == (0)
        test_queue(1, Reactive.runner_task[])
        test_queue(2, Reactive.runner_task[])
    end
end


if !istaskdone(Reactive.runner_task[])
    Reactive.stop()
    fetch(Reactive.runner_task[])
end
