export every, fpswhen, fps, timestamp

# Create a signal of timestamps that updates every delta seconds
#
# Args:
#     delta: interval between updates.
# Returns:
#     a periodically updating timestamp as a signal
function every(delta::Float64)
    i = Input(time())
    update(timer) = push!(i, time())
    t = Timer(update, delta, delta)
    return lift(identity,  i) # prevent push!
end

# Same as the fps function, but you can turn it on and off.
# The first time delta after a pause is always zero, no matter how long the pause was.
#
# Args:
#     test: a switch signal of booleans to turn fps on or off
#     freq: the maximum frequency at which fpswhen should update
# Returns:
#     an signal of Float64 time deltas
function gate(wason_timer::Tuple{Bool, Timer}, ison::Bool, s::Input{Float64}, delta::Float64)
    wason, timer = wason_timer
    (!wason&&ison) && return (ison, Timer(x->push!(s, time()), 0, delta)) # start pushing again
    (wason&&!ison) && (close(timer); return (ison, timer)) # stop it now!
    (ison, timer)
end
function fpswhen(test::Signal{Bool}, freq)
    cond        = test.value
    delta       = 1.0/freq
    time_signal = Input(time())
    timer       = cond ? Timer(x->push!(time_signal, time()), 0, delta) : Timer(identity, 1, 0) # if started with test=false, create dummy timer
    !cond && close(timer) # immediately close timer when condition is false
    foldl(gate, (cond, timer), test, Input(time_signal), Input(delta))
    return foldl(-, time(), time_signal)
end
fpswhen(test, freq) = fpswhen(signal(test), freq)

# Takes a desired number of frames per second and updates
# as quickly as possible at most the desired number of times a second.
#
# Args:
#     freq: the desired fps
# Returns:
#     a signal of time delta between two updates
function fps(freq)
    return fpswhen(Input(true), float(freq))
end

# Timestamp a signal.
#
# Args:
#     s: a signal to timestamp
# Returns:
#     a signal of type (Float64, T) where the first element is the time
#     at which the value (2nd element) got updated.
_timestamp(x) = (time(), x)
function timestamp{T}(s::Signal{T})
    return lift(_timestamp, s)
end
timestamp(s) = timestamp(signal(s))

# Collect signal updates into lists of updates within a given time
# period.
#
# Args:
#    signal: a signal Signal{T}
#    t: the time window
# Returns:
#    A throttled signal of Signal{Vector[T]}
## type ThrottleNode{T} <: Node{Vector{T}}
##     rank::UInt
##     children::Vecto{Signal}
##     signal::Signal{T}
##     window::Float64
##     value::Vector{T}

##     function ThrottleNode(s::Signal{T}, t::Float64)
##         node = new(Reactive.next_rank(), Signal[], s, window, [s.value])
##         Reactive.add_child!(s, node)
##     end
## end
## function update{T}(s::ThrottleNode{T}, parent::Signal{T})
## end

## function throttle{T}(s::Signal{T}, t::Float64)
##     i = Input([s.value])
##     if noBin exists
##         createANewBin which will update the signal in t seconds.
##     else
##         add to bin
##     end
##     return i
## end

# Remove this in a 0.2 release
module Timing
import Reactive: fps, fpswhen, every, timestamp
export fps, fpswhen, every, timestamp
end
