using Reactive

# Stop the runner task
Reactive.stop_event_loop()

include("basics.jl")
#include("gc.jl")
include("call_count.jl")
include("flatten.jl")
include("time.jl")
include("async.jl")
FactCheck.exitstatus()
