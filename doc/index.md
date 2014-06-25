---
title: Introduction
author: Shashi Gowda
order: 1
...

![](Star-On-Machine.jpg)

React.jl is a package for programming with data flows and the propagation of change. It makes event-driven programming simple.

React borrows its design from [Elm](http://elm-lang.org/) ([Functional Reactive Programming](http://elm-lang.org/learn/What-is-FRP.elm)).

# Getting Started

To install the latest release of React, run the following in the Julia REPL.
```{.julia execute="false"}
Pkg.add("React")
```

To start using it, import it:
```{.julia execute="false"}
using React
```
# Signals and the lift operator

The basic currency of React programs are signals. `Signal{T}` is an abstract type that represents a time-varying value of type `T`. You can create signals, combine, filter and merge them using the functions in this library.

An `Input` is the most basic kind of signal: it has no parents and all updates to it are explicit (done through a call to `push!`).

In the examples below we explore how a simple line follower robot could be programmed.

Here are the specifications of the robot:

1. There are 3 sensors: left, middle and right
2. There are 2 DC motors: left and right (the bot is balanced by a castor wheel)

We need to take inputs from the sensors and drive the motors. We start off by creating a signal of sensor values. You can use the `Input` constructor to initialize an input signal with a default value.
```{.julia execute="false"}
# the values signify how much of the line each sensor (left, middle, right) is seeing
sensor_input = Input([0.0, 1.0, 0.0])     # :: Input{Vector{Float64}}
```

The `lift` operator takes a function `f` of arity `n`, optionally an output type and `n` signals, and creates a new signal. The new signal updates when one of the `n` argument signals update. Its value is `f` applied to the values of the input signals.

```{.julia execute="false"}
# v_left function takes as the current sensor readings
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

#  transform the sensor input into a signal of voltages.
left_motor  = lift(v_left,  Float64, sensor_input)
right_motor = lift(v_right, Float64, sensor_input)
```

The `@lift` macro makes this simpler:

```{.julia execute="false"}
left_motor  = @lift sensor_input[1] - sensor_input[3]
right_motor = @lift sensor_input[1] - sensor_input[2]
```

We can now create a signal that updates the voltage across the motors when the voltage signals change.

```{.julia execute="false"}
function set_voltages(left, right)
	write(LEFT_MOTOR_OUTPUT,  left)
	write(RIGHT_MOTOR_OUTPUT, right)
end

@lift set_voltages(left_motor, right_motor)
```

# An Event Loop
Finally, we need to set up an event loop which reads input from the sensors and plumbs it into the data flow we created above.

```{.julia execute="false"}
function read_sensors()
	[read(LEFT_SENSOR_PIN),
     read(MIDDLE_SENSOR_PIN),
     read(RIGHT_SENSOR_PIN)]
end

while true
    # push! changes the value held by an input signal and
    # propagates it through the data flow
    @async push!(sensor_input, read_sensors())
    sleep(0.1)
end
```

See [Timed signals and sampling](#timed-signals-and-sampling) for a more elegant way of doing the same!

# Maintaining State

The following examples deal with a voting system in an election. The voters can either vote for Alice, Bob, or cast an invalid vote.

`foldl` can be used to accumulate a value over time. You might count the number of votes like this:
```{.julia execute="false"}
votes   = Input(:NoVote)    # We use :NoVote to denote the initial case
total   = foldl((acc, vote) -> acc + (vote != :NoVote), 0, votes) # Count all votes
alice   = foldl((acc, vote) -> acc + (vote == :Alice), 0, votes)
bob     = foldl((acc, vote) -> acc + (vote == :Bob),   0, votes)
leading = lift((a, b) -> if a > b ? :Alice : a < b ? :Bob : :Tie, alice, bob)
```

Maintaining a difference is a bit more involved. To find the difference between previous and current value of a signal, you'd do:
```{.julia execute="false"}
function difference(prev, x)
	prev_diff, prev_val = prev
    # x becomes prev_val in the next call
    return (x-prev_val, x)
end

diff = lift(x->x[1], foldl(difference, 0.0, signal))
```

This is a common pattern that arises while writing programs with React. Note that this method has the advantage that all state is explicit. You could accomplish this by using a global variable to store `prev_val`, but that is not recommended.

# Filtering, merging

The `filter` or `dropif` functions can filter a signal based on a predicate function.

```{.julia execute="false"}
# Create a signal of only valid votes
# If the initial votes are invalid, then we return nothing
valid_votes = filter(x -> x != :Invalid, :NoVote, votes)

# Or
valid_votes = dropif(x -> x == :Invalid, :NoVote, votes)
```

`keepwhen` and `dropwhen` functions can be used to filter a signal based on another boolean signal.

```{.julia execute="false"}
keepwhen(poll_open, votes)

# Or
dropwhen(poll_closed, votes)
```

You can merge two or more signals of the same type with `merge`:

```{.julia execute="false"}
# merge votes from all polls
votes = merge(poll1, poll2, poll3)
```

You can drop repeated updates to a signal with `droprepeats`:

```{.julia execute="false"}
leading_norepeat = droprepeats(leading)   # Only changes when the leading candidate changes.
```

# Timed signals and sampling

`React.Timing` module contains some functions to create timed signals.
`every` can be used to create a signal that updates at a certain interval.

```{.julia execute="false"}
# E.g.

every10secs = every(10.0)
```

`every10secs` is a signal of timestamps (Float64) which updates every 10 seconds.

`sampleon` function takes two signals and samples the second signal when the first one changes.

```{.julia execute="false"}
# E.g.

# Update to the leading candidate every 10 seconds
periodic_leading = sampleon(every10secs, leading)
```

While `every` guarrantees the interval, `fps` tries to update at a certain maximum rate.

```{.julia execute="false"}
# E.g.

fps10 = fps(10.0)
```

We can use `fps` to simplify the signal loop in our robot example above:

```{.julia execute="false"}
# fps returns the time delta between the past two frames
# This could be useful in animations or plotting. We ignore it here.
sensor_input = lift((delta) -> read_sensors(), fps(10.0))
```

`fpswhen` takes a boolean signal as the first argument and stops the timer when this signal becomes false.

```{.julia execute="false"}
# assume circuit completes if none of the sensors can see the line
circuit_not_complete = lift(s -> sum(s) != 0.0, sensor_inputs)
sensor_input = lift(read_sensors, fpswhen(circuit_not_complete, 10.0))
```

this stops reading the input (and hence moving the bot) when the circuit is complete.

`timestamp` function can be used to timestamp any signal.

```{.julia execute="false"}
# E.g.
timestamped_votes = timestamp(votes)
```
`timestamped_votes` is a signal of `(timestamp, vote)` where `timestamp` is a `Float64` timestamp denoting when the `vote` came in.

# Possible uses of React
We have seen very simplistic examples above. React is general enough to help you build many other apps driven by events. Some use cases off the top of my head:

* Interactive user interfaces (watch out for [Interact.jl](https://github.com/shashi/Interact.jl))
* Animations
* Robotics and automation
* Queueing systems and service oriented apps

# Reporting Bugs

Let me know about any bugs, counterintuitive behavior, or enhancements you'd like by [filing a bug](https://github.com/shashi/React.jl/issues/new) on github.
