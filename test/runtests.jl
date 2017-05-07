using Reactive
using FactCheck

# Stop the runner task

if !istaskdone(Reactive.runner_task)
    Reactive.stop()
    wait(Reactive.runner_task)
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
FactCheck.exitstatus()
