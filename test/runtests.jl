using Reactive

# Stop the runner task
try
    println("Killing ", Reactive.runner_task) # the task switch caused here is required!
    Base.throwto(Reactive.runner_task, InterruptException())
catch
end

include("basics.jl")
#include("gc.jl")
include("call_count.jl")
include("flatten.jl")
include("time.jl")
include("async.jl")
FactCheck.exitstatus()
