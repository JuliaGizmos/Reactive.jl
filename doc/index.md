---
title: Introduction - Reactive.jl
author: Shashi Gowda
order: 1
...

![](Star-On-Machine.jpg)

Reactive.jl is a Julia package for [Reactive Programming](http://en.wikipedia.org/Reactive_Programming). It makes writing event-driven programs simple.

Reactive borrows its design from [Elm](http://elm-lang.org/) (see also [Functional Reactive Programming](http://elm-lang.org/learn/What-is-FRP.elm)).

# Getting Started

To install the latest release of Reactive, run the following in the Julia REPL.
```{.julia execute="false"}
Pkg.add("Reactive")
```

To start using it, import it:
```julia
using Reactive
```
# A Tutorial Introduction

## Signals

<!-- the dot language mapping of signal types:
		input: 'hexagon'
		lift: 'invtrapezium'
		foldp: 'rect'
		sampleOn: 'house'
		constant: 'none'
		dropRepeats: 'doubleoctagon';
		merge: 'invtriangle';
		default: 'ellipse';
-->
The basic currency of Reactive programs is the signal. `Signal{T}` is an abstract type that represents a time-varying value of type `T`. You can create, mix and mash `Signal`s using Reactive.

An `Input` is the most basic kind of signal: it has no *parents*--all updates to it are explicitly done through a call to `push!`.
```{.julia execute="false"}
# E.g.
x = Input(0)
typeof(x)
# => Input{Int64}
super(Input{Int64})
# => Signal{Int64}
x.value
# => 0
push!(x, 2)
x.value
# => 2
```

## Do you even lift?

The `lift` operator can be used to transform one signal into another.

```{.julia execute="false"}
xsquared = lift(a -> a*a, Int, x)
typeof(xsquared)
# => Lift{Int64}
super(Reactive.Lift{Int64})
# => Signal{Int64}
xsquared.value
# => 4
```

The type of the lifted signal can be given as the second argument to `lift`. It is assumed to be Any if omitted.

Now for every value `x` takes, `xsquared` will hold its square.
```{.julia execute="false"}
push!(x, 3)
xsquared.value
# => 9
```
`lift` can take more than one signal as argument.
```{.julia execute="false"}
y = lift((a, b) -> a + b, Int, x, xsquared)
y.value
# => 12
```

**Example: A stupid line-droid**

In the examples below we explore how a simple line-follower robot could be programmed with Reactive.

Here are the specifications of the robot:

1. There are 3 sensors: left, middle and right
2. There are 2 DC motors: left and right (the bot is balanced by a castor wheel)

We start off by creating a signal of sensor values.
```{.julia execute="false"}
# the values signify how much of the line each sensor (left, middle, right) is seeing
sensor_input = Input([0.0, 1.0, 0.0])     # :: Input{Vector{Float64}}
```
Then create motor voltages from sensor readings.
```{.julia execute="false"}

function v_left(sensors)
   # slow down when left sensor is seeing a lot of the line
   # -ve voltage turns the wheel backwards
   # this could, of course, be [more complicated than this](http://www.societyofrobots.com/member_tutorials/book/export/html/350).
   sensors[2] - sensors[1]
end

# Similarly
function v_right(sensors)
   # slow down when the right sensor is seeing the line
   sensors[2] - sensors[3]
end

left_motor  = lift(v_left,  Float64, sensor_input)
right_motor = lift(v_right, Float64, sensor_input)
```

The `@lift` macro makes this simpler:

```{.julia execute="false"}
left_motor  = @lift sensor_input[1] - sensor_input[3]
right_motor = @lift sensor_input[1] - sensor_input[2]
```

We now ask the bot to apply the voltages across its two wheels:
```{.julia execute="false"}
function set_voltages(left, right)
	write(LEFT_MOTOR_OUTPUT,  left)
	write(RIGHT_MOTOR_OUTPUT, right)
end

@lift set_voltages(left_motor, right_motor)
```

## The Event Loop
Finally, we need to set up a loop which reads input from the sensors and plumbs it into the data flow we created above.

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

## Maintaining State

**Example: A Voting System**
The following examples deal with a voting system in an election. The voters can either vote for Alice, Bob, or cast an invalid vote.

[`foldl`](api.html#foldl) can be used to accumulate a value over time. You might count the number of votes like this:
```{.julia execute="false"}
votes   = Input(:NoVote)    # We use :NoVote to denote the initial case
total   = foldl((acc, vote) -> acc + 1, 0, votes) # Count all votes
alice   = foldl((acc, vote) -> acc + (vote == :Alice), 0, votes)
bob     = foldl((acc, vote) -> acc + (vote == :Bob),   0, votes)
leading = lift((a, b) -> a > b ? :Alice : a < b ? :Bob : :Tie, alice, bob)
```

Maintaining a difference between two updates is a bit more involved. To find the difference between previous and current value of a signal, you'd do:
```{.julia execute="false"}
function difference(prev, x)
	prev_diff, prev_val = prev
    # x becomes prev_val in the next call
    return (x-prev_val, x)
end

diff = lift(x->x[1], foldl(difference, 0.0, signal))
```

Note that this method has the advantage that all state is explicit. You could accomplish this by using a global variable to store `prev_val`, but that is not recommended.

## Filter and merge

The [`filter`](api.html#filter) or [`dropif`](api.html#dropif) functions can filter a signal based on a predicate function.

```{.julia execute="false"}
# Create a signal of only valid votes
# If the initial votes are invalid, we use :NoVote
valid_votes = filter(x -> x != :Invalid, :NoVote, votes)

# Or
valid_votes = dropif(x -> x == :Invalid, :NoVote, votes)
```
To drop certain updates to a signal you can use [`keepwhen`](api.html#keepwhen) and [`dropwhen`](api.html#dropwhen). You could stop collecting votes when there is a security breach like this:

```{.julia execute="false"}
secure_votes = keepwhen(everything_secure, votes)

# Or
secure_votes = dropwhen(security_breached, votes)
```

[`merge`](api.html#merge) merges multiple signals of the same type. To collect all votes from 3 polls into a single signal you'd do something like

```{.julia execute="false"}
votes = merge(poll1_votes, poll2_votes, poll3_votes)
```

You can drop repeated updates to a signal with [`droprepeats`](api.html#droprepeats):

```{.julia execute="false"}
leading_norepeat = droprepeats(leading)
```
`leading_norepeat` only updates when the leading candidate changes.

Finally,
```{.julia execute="false"}
lift(show_on_TV, alice, bob, stats)
```

## Timed signals and sampling

Reactive provides functions to create timed signals.
[`every`](api.html#every) can be used to create a signal that updates at a certain interval.

```{.julia execute="false"}
# E.g.

every10secs = every(10.0)
```

`every10secs` is a signal of timestamps (Float64) which updates every 10 seconds.

[`sampleon`](api.html#sampleon) function takes two signals and samples the second signal when the first one changes.

```{.julia execute="false"}
# E.g.

# Update to the leading candidate every 10 seconds
periodic_leading = sampleon(every10secs, leading)
```

While `every` guarrantees the interval, [`fps`](api.html#fps) tries to update at a certain maximum rate.

```{.julia execute="false"}
# E.g.

fps10 = fps(10.0)
```

We can use `fps` to simplify the [event loop](#the-event-loop) in our robot example above:

```{.julia execute="false"}
# fps returns the time delta between the past two frames
# This could be useful in animations or plotting. We ignore it here.
sensor_input = lift((delta) -> read_sensors(), fps(10.0))
```

[`fpswhen`](api.html#fpswhen) takes a boolean signal as the first argument and stops the timer when this signal becomes false.

```{.julia execute="false"}
# assume circuit completes if none of the sensors can see the line
circuit_not_complete = lift(s -> sum(s) != 0.0, sensor_inputs)
sensor_input = lift(read_sensors, fpswhen(circuit_not_complete, 10.0))
```

this stops reading the input (and hence moving the bot) when the circuit is complete.

[`timestamp`](api.html#timestamp) function can be used to timestamp any signal.

```{.julia execute="false"}
# E.g.
timestamped_votes = timestamp(votes)
```
`timestamped_votes` is a signal of `(timestamp, vote)` where `timestamp` is a `Float64` timestamp denoting when the `vote` came in.

# Possible uses
I am currently using Reactive to build interactive widgets on [IJulia](http://github.com/JuliaLang/IJulia.jl). Reactive is aimed at making event-driven programming simple. You could use Reactive to build:

* Interactive user interfaces (watch out for [Interact.jl](https://github.com/shashi/Interact.jl))
* Animations
* Robotics and automation
* Queueing systems and service-oriented apps

# Reporting Bugs

Let me know about any bugs, counterintuitive behavior, or enhancements you'd like by [filing a bug](https://github.com/shashi/Reactive.jl/issues/new) on github.
