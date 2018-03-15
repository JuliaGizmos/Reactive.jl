---
title: Introduction - Reactive.jl
author: Shashi Gowda
order: 1
...

![](Star-On-Machine.jpg)

Reactive.jl is a Julia package for [Reactive Programming](https://en.wikipedia.org/wiki/Reactive_programming). It makes writing event-driven programs simple.

Reactive borrows its vocabulary from [Elm](http://elm-lang.org/).

# What is reactive programming?

*Reactive programming* is a way of creating event-driven programs in terms of **streams of data**. The streams in this package are called Signals, the name signifies the fact that they always have a value, and are conceptually continuous like electrical signals. For example, a keyboard gives out a *signal of keys pressed*, a timer might give out a *signal of timestamps*, a database can consume a *signal of queries* and so on. Reactive also provides functions for common operations on signals such as transforming, filtering, merging, sampling, and throttling.


# Getting Started

To install the latest release of Reactive, run the following in the Julia REPL.
```{.julia execute="false"}
Pkg.add("Reactive")
```

To start using it, import it:
```{.julia execute="false"}

using Reactive
```
# A Tutorial Introduction

## Signals

<!-- the dot language mapping of signal types:
		input: 'hexagon'
		map: 'invtrapezium'
		foldp: 'rect'
		sampleOn: 'house'
		constant: 'none'
		dropRepeats: 'doubleoctagon';
		merge: 'invtriangle';
		default: 'ellipse';
-->
The basic currency of Reactive programs is the signal. `Signal{T}` represents a time-varying value of type `T`.

A signal can be created using the `Signal` constructor, and must be given an inital value.
```{.julia execute="false"}
# E.g.
julia> x = Signal(0)
Signal{Int64}(0, nactions=0)

julia> value(x)
0
```

to update the value in a signal, use the `push!` function on signals.

```{.julia execute="false"}
# E.g.
julia> push!(x, 42)

julia> value(x)
42
```

the `push!` function updates the signal asynchronously via a central channel of updates. Below we will learn ways to derive dependent signals from one or more signals that already exist.


## Derived signals

The `map` function can be used to transform signals by applying a function.

```{.julia execute="false"}
julia> xsquared = map(a -> a*a, x)

julia> value(xsquared)
1764 # 42^2

```

Now for every value of `x`, `xsquared` will hold its square.
```{.julia execute="false"}
julia> push!(x, 3)

julia> value(xsquared)
9
```

The type of the `map` signal can be specified using a keyword argument `typ=T` to `map`. If omitted, it is determined from the type returned by the function, using the current `value`s of its inputs. If you want to set an initial value without computing it from the current value of the input signals, you can specify it using the `init` keyword argument. `map` can take more than one signals as argument. Here is a demonstration of these three points.

```{.julia execute="false"}
julia> y = map(+, x, xsquared; typ=Float64, init=0)

julia> value(y) # Will give the initial value
0.0

julia> push!(x, 4)

julia> value(y) # will be 4 + 4^2
20.0
```

Note that, signal nodes that do not have any reference in Reactive are admissible to [garbage collection](https://en.wikipedia.org/wiki/Garbage_collection) and subsequent termination of updates. So if you are creating a signal with `map` and to do some side effect (like printing) and don't plan to keep a reference to it, it may be stopped in the next GC pass. To prevent this from happening, you can *preserve* a signal using the `preserve` function.

```{.julia execute="false"}
julia> preserve(map(println, x))
Signal{Void}(nothing, nactions=0) # the type is Void because that's the return type of println
4

julia> push!(x, 25)
25 # printed by the above signal
```

`foreach(f, x)` is a shorthand for `preserve(map(f, x))`. So the above could also have been written as `foreach(println, x)`.

`map` is a very useful function on signals. We will see an example of map below.

**Example: A simple animation**

Let's use `map` to create an animation of a bouncing ball using [Compose.jl](http://composejl.org).

Our goal is to create a signal of Compose pictures that updates over time. To do this we will first create a function which given a time `t`, returns a picture of the ball at that time `t`. We will worry about updating this time `t` later.

```{.julia execute="false"}
function drawball(t)
  y = 1-abs(sin(t)) # The y coordinate.
  compose(context(), circle(0.5, y, 0.04))
end
```

In this function the `y` coordinate of the ball at any time `t` is `1-abs(sin(t))` - when you plot this function over `t`, you can see that it looks like the bouncing of a ball.

Next, we need a signal that updates at a reasonable rate every second. That's where the `fps` function comes in handy. `fps(rate)` returns a signal which updates `rate` times every second.

```{.julia execute="false"}
julia> ticks = fps(60)
```

The `ticks` signal itself updates to the time elapsed between the current update and the previous update, although this is useful, for the sake of this example, we will use `map` to create a signal of time stamps from this signal.

```{.julia execute="false"}
julia> timestamps = map(_ -> time(), ticks)
```

Now that we have a signal of timestamps, we can use this to create a signal of compose graphics which will be our animation.

```{.julia execute="false"}
julia> anim = map(drawball, timestamps)
```

**Try it.** The [Interact](https://github.com/JuliaGizmos/Interact.jl) package allows you to render `Signal` objects as they update over time in IJulia notebooks. Try the following code in an IJulia notebook to see the animation we just created.

```{.julia execute="false"}
using Reactive, Interact, Compose

function drawball(t)
  y = 1-abs(sin(t)) # The y coordinate.
  compose(context(), circle(0.5, y, 0.04))
end

ticks = fps(60)
timestamps = map(_ -> time(), ticks)
map(drawball, timestamps)
```

The complete example points to the usual structure of programs written with Reactive. It usually consists of stateless functions (such as `drawball`) and then wiring input signals to these stateless functions to create the output signal. Below we will see some more involved examples with other operations on signals.

## Maintaining State

[`foldp`](api.html#foldp) can be used to accumulate a value over time. You might have learned about [foldl and foldr](https://en.wikipedia.org/wiki/Fold_%28higher-order_function%29) functions on collection objects. `foldp` is a similar function, the name stands for "fold over past values".

Let's look at how it works: `y = foldp(f, init, x)`

Here, `y` is a signal whose initial value is `init`, and when the signal `x` updates, `f` is applied to the current value of `y` and the current value of `x` and the result is again stored in `y`.

As an example:

```{.julia execute="false"}
julia> x = Signal(0)

julia> y = foldp(+, 0, x)

julia> push!(x, 1)

julia> value(y)
1

julia> push!(x, 2)

julia> value(y)
3

julia> push!(x, 3)

julia> value(y)
6
```

When we wrote `y=foldp(+, 0, x)` we created a signal `y` which collects updates to `x` using the function `+` and starting from `0`. In other words, `y` holds the sum of all updates to `x`.

We can rewrite the above bouncing ball example by summing time-deltas given by `fps` instead of calling time() as follows.
```{.julia execute="false"}
ticks = fps(60)
t = foldp(+, 0.0, ticks)
map(drawball, t)
```

If one were to use `fpswhen(switch, 60)` instead of `fps(60)` here to start and stop the fps signal with respect to some other boolean signal called `switch`, after switching off the animation and switching it on, the ball would start off where it was paused with the foldp version of the animation.

## Filtering

Another important operator on signals is `filter`. It can be used to filter only those updates which are true according to a given condition. The signature is 

`filter{T}(f::Function, default, input::Reactive.Signal{T})`

The default value is needed, to make sure that the filtered signal does not end up empty.

For instance `filter(a -> a % 2 == 0, 0, x)` will only keep even updates to the integer signal `x`.

A variation of `filter` called `filterwhen` lets you keep updates to a signal only when another boolean signal is true.

`filterwhen(switch_signal, default, signal_to_filter)`

## Merging

`d = merge(a,b,c)` will merge updates to `a`, `b` and `c` to produce a signle signal `d`.

## Drop repeats

You can drop repeated updates to a signal with [`droprepeats`](api.html#droprepeats)

```{.julia execute="false"}
julia> p = Signal(0)

julia> d = droprepeats(p)

julia> foreach(println, d)

julia> push!(d, 0)

julia> push!(d, 1)
1

julia> push!(d, 1)
```
Notice how the  value of d did not get printed when it didn't change from the previous value.

**Example: A Voting System**

To illustrate the functions described above, we will try to model a voting system in an electorate using Reactive. The voters can either vote for Alice, Bob, or cast an invalid vote.

Input `votes` signal:

```{.julia execute="false"}
votes = Signal(:NoVote)    # Let's :NoVote to denote the initial case
```

Now we can split the vote stream into votes for alice and those for bob.

```{.julia execute="false"}
alice_votes = filter(v -> v == :Alice, :NoVote, votes)
bob_votes   = filter(v -> v == :Bob, :NoVote, votes)
```

Now let's count the votes cast for alice and bob using foldp

```{.julia execute="false"}
function count(cnt, _)
  cnt+1
end

alice_count = foldp(count, 0, alice_votes)
bob_count = foldp(count, 0, bob_votes)
```

We can use the counts to show at real time who is leading the election.

```{.julia execute="false"}
leading = map(alice_count, bob_count) do a, b
  if a > b
    :Alice
  elseif b > a
    :Bob
  else
    :Tie
  end
end
```

Notice the use of [`do` block](http://docs.julialang.org/en/release-0.4/manual/functions/#do-block-syntax-for-function-arguments) syntax here. `do` is a short-hand for creating anonymous functions and passing it as the first argument in a function call (here, to `map`). It's often useful to improve readability.

Notice that the `leading` signal will update on every valid vote received. This is not ideal if we want to say broadcast it to someone over a slow connection, which will result in sending the same value over and over again. To alleviate this problem, we can use the droprepeats function.

```{.julia execute="false"}
norepeats = droprepeats(leading)
```

To demonstrate the use of `filterwhen` we will conceive a global `election_switch` signal which can be used to turn voting on or turn off. One could use this switch to stop registering votes before and after the designated time for votes, for example.

```{.julia execute="false"}
secure_votes = filterwhen(election_switch, :NoVote, votes)
```
`secure_votes` will only update when `value(election_switch)` is `true`.

Finally, to demonstrate the use of merge, let's imagine there are multiple polling stations for this election and we would like to merge votes coming in from all of them. This is pretty straightforward:

```{.julia execute="false"}
votes = merge(poll1_votes, poll2_votes, poll3_votes)
```


## Time, sampling and throttle

Reactive provides functions to create timed signals.
[`every`](api.html#every) can be used to create a signal that updates at a certain interval.

```{.julia execute="false"}
# E.g.

every10secs = every(10.0)
```

`every10secs` is a signal of timestamps (Float64) which updates every 10 seconds.

[`sampleon`](api.html#sampleon) function takes two signals and samples the second signal when the first one changes.

Let's say in our voting example, we want a signal of the leading voted candidate in the election but would like an update at most every 10 seconds, one could do it like this:

```{.julia execute="false"}
# E.g.
periodic_leading = sampleon(every10secs, leading)
```

`throttle` lets you limit updates to a signal to a maximum of one update in a specified interval of time.

Suppose you are receiving an input from a sensor and the sampling rate of it can vary and sometimes becomes too high for your program to handle, you can use throttle to down sample it if the frequency of updates become too high.

```{.julia execute="false"}
throttle(1/100, sensor_input) # Update at most once in 10ms
```

# Reactive in the wild
Reactive is a great substrate to build interactive GUI libraries. Here are a few projects that make use of Reactive:

* [Interact.jl](https://github.com/JuliaGizmos/Interact.jl)
* [Escher.jl](https://github.com/shashi/Escher.jl)
* [GLPlot.jl](https://github.com/SimonDanisch/GLPlot.jl)

It could also be potentially used for other projects that require any kind of event handling: controlling robots, making music or simulations.

# Reporting Bugs

Let me know about any bugs, counterintuitive behavior, or enhancements you'd like by [filing a bug](https://github.com/shashi/Reactive.jl/issues/new) on github.
