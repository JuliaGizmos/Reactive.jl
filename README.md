# React

[![Build Status](https://travis-ci.org/shashi/React.jl.png)](https://travis-ci.org/shashi/React.jl)

React.jl is a library for programming with data flows and the propagation of change. It makes event driven programming simple.

React.jl borrows its design from [Elm](http://elm-lang.org/) ([FRP](http://elm-lang.org/learn/What-is-FRP.elm)).

## Installation

```julia
Pkg.add("React")
```

## Usage

### Signal type
A value of type `Signal{T}` represents a time-varying value of type T. Signal is an abstract type. Functions `Input`, `lift`, `foldl`, `sampleon` and [others](#api) all create values that are a subtypes of Signal.

A simple line follower robot with 3 "line sensors" and 2 motors might be programmed like this:
```julia
# Suppose the sensor readings come in a float array signifying
# what proportion of the line each sensor is seeing: left, middle, right
sensor_input = Input([0.0, 1.0, 0.0]) # :: Input{Vector{Float64}}
```

We can create output signals from the sensor readings
```julia
# v_left function takes as input the current sensor readings
# and returns the voltage to be applied across the left DC motor
function v_left(sensors)
   # slow down when left sensor is seeing a lot of the line
   # -ve voltage turns the wheel backwards
   # this could, of course, be [more complicated than this](http://www.societyofrobots.com/member_tutorials/book/export/html/350).
   sensors[2] - sensors[1]
end

# similarly, v_right converts sensor readings into the voltage
# applied across right motor
function v_right(sensors)
   sensors[2] - sensors[3]
end

# lift operator can be used to transform the sensor input into
# a signal of voltages.
left_motor  = lift(v_left,  Float64, sensor_input)
right_motor = lift(v_right, Float64, sensor_input)
```

The lift macro makes this simpler:

```julia
left_motor  = @lift sensor_input[1] - sensor_input[3]
right_motor = @lift sensor_input[1] - sensor_input[2]
```

We can now pipe the output signals into the motors.
```julia
function set_voltages(left, right)
	write(LEFT_MOTOR_OUTPUT,  left)
	write(RIGHT_MOTOR_OUTPUT, right)
end

@lift set_voltages(left_motor, right_motor)
```

### The Event Loop
Finally, we need to set up an event loop which reads input and plumbs it into the data flow we created above.

```julia
while true
    # push! changes the value held by an input signal and
    # propagates it through the data flow
    @async push!(sensor_input,
            [read(LEFT_SENSOR_PIN),
             read(MIDDLE_SENSOR_PIN),
             read(RIGHT_SENSOR_PIN)])
    sleep(0.1)
end
```

### State
The following examples deal with a voting system in an election. The voters can either vote for Alice, Bob, or it might be invalid. `foldl` can be used to accumulate a value over time. You might count the number of votes like this:
```julia
votes   = Input(:Invalid)
total   = foldl((acc, vote) -> acc + 1, 0, votes)
alice   = foldl((acc, vote) -> acc + (vote == :Alice), 0, votes)
bob     = foldl((acc, vote) -> acc + (vote == :Bob),   0, votes)
leading = lift((a, b) -> if a > b ? :Alice : a < b ? :Bob : :Tie, alice, bob)
```

`foldl`s requiring saved states are a bit more involved. Suppose we want to find the time between the last two votes. We would first need to timestamp the votes.
```julia
# Timing.timestamp creates a signal of type (Float64, Symbol)
vote_times = Timing.timestamp(votes)
timestamps = lift(v->v[1], vote_times)
```
And then use `foldl` to maintain a difference, and also save the current value
```julia
function difference(state, t)
     prev_diff, prev_t = state
     # we must save the current value for the next update
     return (t-prev_t, t)
end

diff = lift(x->x[1], foldl(difference, (0, time()), vote_times))
```

### Filtering, merging and sampling

The `filter` function can filter updates to a signal with a predicate

```julia
# Create a signal of only valid votes
# If the first vote is invalid, then we return nothing
valid_votes = filter(x -> x != :Invalid, nothing, votes)
```

You can merge two or more signals of the same type with `merge`:

```julia
# merge votes from all the polling booths
votes = merge(poll1, poll2, poll3)
```

## API
Find out what else you can do with React.jl: [API documentation](http://shashi.github.io/React.jl).
