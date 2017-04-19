using Reactive

# Stop the runner task

if !istaskdone(Reactive.runner_task)
    Reactive.stop()
    wait(Reactive.runner_task)
end

include("basics.jl")
#include("gc.jl")
include("call_count.jl")
include("flatten.jl")
include("time.jl")
include("async.jl")
FactCheck.exitstatus()
