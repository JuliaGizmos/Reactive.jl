using Reactive
if VERSION < v"0.7.0-DEV.2005"
    using Base.Test
else
    using Test
end
# Stop the runner task

using Reactive: wait07


@testset "Queue runner" begin
    @test (istaskdone(Reactive.runner_task[])) == (false)
    Reactive.stop()
    @test (istaskdone(Reactive.runner_task[])) == (true)
end


step() = Reactive.run(1)
queue_size() = Base.n_avail(Reactive._messages)
number() = round(Int, rand()*1000)

include("basics.jl")
include("push_to_non_input.jl")
# include("gc.jl")
include("node_order.jl")
include("call_count.jl")
include("flatten.jl")
include("time.jl")
include("async.jl")
include("queue_runner.jl")
