If you're new to Reactive or functionally-reactive programming in
general, it pays to spend some time exploring Reactive's programming
paradigm.  This documents a set of experiments conducted while
rewriting ImageView.jl using Reactive and Gtk; perhaps they will serve
as useful demonstrations for others.

## Example 1: throttling redraws

In an interactive image viewer, drawing an image on the canvas might
depend on many variables: the current contrast settings, the x- and
y-intervals selected by zooming, and (for images with transparency)
the choice of a colored or checkerboard background.  Whenever one of
these variables updates, we want to redraw the image.  However, quite
commonly we might update several of these variables "simultaneously":
for example, selecting a zoom region with the mouse will update both
the x- and y-intervals.  While we could write a function

    set_x_and_y!(imagecanvas, xlim, ylim)
        imagecanvas.xlim = xlim
        imagecanvas.ylim = ylim
        draw(imagecanvas)
    end

this approach has disadvantages particularly when changes to
`imagecanvas` are generated from code rather than user interaction:
while updates of `xlim` and `ylim` are now coupled, code that affects
both `xlim` and, say, the contrast settings will generate needless
redraws.

A simple approach that does not require any coupling is to use
*scheduled* redraws: any time a relevant setting changes, indicate
that the canvas needs to be redrawn, but don't perform that redraw
immediately.  Instead, schedule it for some (short) time in the
future, and limit (`throttle`) redraws to some minimum time interval.

Let's explore a couple of different implementations of this basic
idea. First, let's look at an approach that uses Reactive just to
manage the updates---this is a hybrid between reactive-programming and
state-dependent approaches.

```jl
module TwoStates

using Reactive

export Canvas, state1!, state2!

type Canvas{S<:IO}
    io::S
    state1::Int
    state2::Int
    update::Node{Bool}  # push! a value here any time the canvas needs redrawing

    function Canvas(io::S, s1::Integer, s2::Integer)
        update = Node(true)
        c = new(io, s1, s2, update)
        throttled = throttle(1/60, update)
        # The node that gets returned by `map` will be garbage-collected
        # unless we call `preserve` on it. An alternative is to store
        # this node somewhere (e.g., see the "TwoSharedNodes" example below).
        Reactive.preserve(map(x->println(c.io, "state1: $(c.state1); state2: $(c.state2)"), throttled))
        c
    end
end

Canvas(io::IO, s1, s2) = Canvas{typeof(io)}(io, s1, s2)

state1!(c::Canvas, val) = (c.state1 = val; push!(c.update, true); val)
state2!(c::Canvas, val) = (c.state2 = val; push!(c.update, true); val)

end  # module


# OK, let's try it!

using Reactive, TwoStates

c = Canvas(STDOUT, 1, 1)
state1!(c, 5)
sleep(0.1)

state1!(c, 7)
state2!(c, -3)
sleep(0.1)
```

Here's the output:
```jl
julia> include("twostates.jl")
state1: 1; state2: 1
state1: 5; state2: 1
state1: 7; state2: -3

julia>
```

The first output line was triggered by creating the `Canvas`; the
second line was triggered by the first `state1!` call. Most likely,
both of these outputs were produced during the first `sleep`, during
which time Reactive's event cue runs. The next two updates, of both
`state1` and `state2` run, and once again during the `sleep` the event
queue fires and processes updates; it produces a single line of output
for the updates to both states. Without the `throttle`, we instead
would have gotten

```jl
julia> include("twostates.jl")
state1: 1; state2: 1
state1: 5; state2: 1
state1: 7; state2: -3
state1: 7; state2: -3

julia>
```

Without `throttle`, each `state!` call generated a corresponding line
of output.

Interestingly, the output produced by the second update of `signal1`
also included the consequences of updating `signal2`: this is because
the updates happened before the event loop fired again, so by the time
the `println` statement ran both values had already been updated.
In some circumstances (like this one), this behavior might be fine or
even desirable; in other cases, such behavior could be a source of
bugs.

So in the spirit of exploration, let's look at a second implementation
that preserves history:

```jl
module TwoNodes

using Reactive

export Canvas, state1!, state2!

type Canvas{S<:IO}
    io::S
    state1::Node{Int}
    state2::Node{Int}

    function Canvas(io::S, s1::Integer, s2::Integer)
        n1, n2 = Node(Int, s1), Node(Int, s2)
        c = new(io, n1, n2)
        combined = merge(n1, n2)
        throttled = throttle(1/60, combined)
        Reactive.preserve(map(x->println(c.io, "state1: $(value(c.state1)); state2: $(value(c.state2))"), throttled))
        c
    end
end

Canvas(io::IO, s1, s2) = Canvas{typeof(io)}(io, s1, s2)

state1!(c::Canvas, val) = push!(c.state1, val)
state2!(c::Canvas, val) = push!(c.state2, val)

end  # module

using Reactive, TwoNodes

c = Canvas(STDOUT, 1, 1)
state1!(c, 5)
sleep(0.1)

state1!(c, 7)
state2!(c, -3)
sleep(0.1)
```

Note that the implementation of the `state!` functions was simpler
here.  With `throttle` we again get the same output:

```jl
julia> include("twonodes.jl")
state1: 1; state2: 1
state1: 5; state2: 1
state1: 7; state2: -3

julia>
```

but this time, without `throttle` we get output that respects the history:

```jl
julia> include("twonodes.jl")
state1: 1; state2: 1
state1: 5; state2: 1
state1: 7; state2: 1
state1: 7; state2: -3

julia>
```

## Example 2: sharing state

Suppose we have two `Canvas`es that we want to couple together: for
example, you might want to show two views of the same image, one in
"raw" form and the other "annotated" by some kind of image processing
algorithm.  If you zoom in on one canvas, you might like to
automatically zoom in on the same region in the other canvas.

One option would be to create the two Canvases using `Node`s defined
by the user; if the users supplies the same `Node` for two Canvases,
they will share the same state.  Alternatively, we can `bind!` two
nodes together.  Here is a demonstration of both approaches:

```jl
module TwoSharedNodes

using Reactive

export Canvas, state1!, state2!

type Canvas{S<:IO}
    io::S
    name::ASCIIString
    state1::Node{Int}
    state2::Node{Int}
    update

    Canvas(io::S, name, s1, s2) = Canvas(io, name, node(Int, s1), node(Int, s2))
    function Canvas(io::S, name, n1::Node, n2::Node)
        c = new(io, name, n1, n2)
        combined = merge(n1, n2)
        throttled = throttle(1/60, combined)
        c.update = map(x->println(c.io, "$(c.name): state1=$(value(c.state1)), state2=$(value(c.state2))"), throttled)
        c
    end
end

node{T}(::Type{T}, val) = Node(T, val)
node(::Type, n::Node) = n

Canvas(io::IO, name, s1, s2) = Canvas{typeof(io)}(io, name, s1, s2)

state1!(c::Canvas, val) = push!(c.state1, val)
state2!(c::Canvas, val) = push!(c.state2, val)

end  # module

using Reactive, TwoSharedNodes

n2 = Node(22)
c1 = Canvas(STDOUT, "canvas1", 1, n2)
c2 = Canvas(STDOUT, "canvas2", 2, n2)
state2!(c1, 33)
sleep(0.1)
println("slept")

state1!(c1, 7)
state2!(c2, -3)
sleep(0.1)
println("slept")

# Let's try the other approach
println("Making new canvases to demonstrate bind!")
c1 = Canvas(STDOUT, "canvas1", 1, 44)
c2 = Canvas(STDOUT, "canvas2", 2, 55)
sleep(0.1)
println("slept")
bind!(c1.state2, c2.state2)
sleep(0.1)
println("slept")
push!(c1.state2, 66)
sleep(0.1)
println("slept")
# Now let's unbind them
println("decoupling canvases")
unbind!(c1.state2, c2.state2)
sleep(0.1)
println("slept")
state2!(c2, -5)
sleep(0.1)
println("slept")
state2!(c1, -7)
sleep(0.1)
println("slept")
```

Except for the added comment, the output from this script is

```jl
julia> include("twosharednodes.jl")
canvas1: state1=1, state2=22
canvas2: state1=2, state2=22
canvas1: state1=1, state2=33
canvas2: state1=2, state2=33
slept
canvas1: state1=7, state2=-3
canvas2: state1=2, state2=-3
slept
Making new canvases to demonstrate bind!
canvas1: state1=1, state2=44
canvas2: state1=2, state2=55
slept
slept           # Note: no update here
canvas2: state1=2, state2=66
canvas1: state1=1, state2=66
slept
decoupling canvases
slept
canvas2: state1=2, state2=-5
slept
canvas1: state1=1, state2=-7
slept

julia>
```

You can see that until we decoupled them, updating state2 triggered
updates to both Canvases.  Note also that `bind!` affects future
`push!` statements without altering the current setting of the nodes.
