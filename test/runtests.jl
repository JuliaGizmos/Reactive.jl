using Reactive

# Stop the runner task
try
    throwto(Reactive.runner_task, InterruptException())
catch
end

include("basics.jl")
#include("gc.jl")
include("call_count.jl")
include("flatten.jl")
include("time.jl")
FactCheck.exitstatus()
