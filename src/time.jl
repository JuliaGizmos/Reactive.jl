export every, fps, fpswhen, throttle, debounce

"""
```
debounce(dt, input, f=(acc,x)->x, init=value(input), reinit=x->x;
            typ=typeof(init), name=auto_name!(string("debounce ",dt,"s"), input))
```

Creates a signal that will delay updating until `dt` seconds have passed since the last time `input` has updated. By default, the debounce signal holds the last update of the `input` signal since the debounce signal last updated.

This behavior can be changed by the `f`, `init` and `reinit` arguments. The `init` and `f` functions are similar to `init` and `f` in `foldp`. `reinit` is called after the debounce sends an update, to reinitialize the initial value for accumulation, it gets one argument, the previous accumulated value.

For example
    `y = debounce(0.2, x, push!, Int[], _->Int[])`
will accumulate a vector of updates to the integer signal `x` and push it after `x` is inactive (doesn't update) for 0.2 seconds.

"""
function debounce(dt, node::Signal{T}, f=(acc,x)->x, init=value(node),
        reinit=x->x; typ=typeof(init), name=auto_name!("debounce $(dt)s", node)) where T
    # we don't add `node` as a parent of throttle, as the action is added to the
    # `node` itself, which pushes to the output node at the appropriate time.
    output = Signal(typ, init, (); name=name)
    throttle_connect(dt, output, node, f, init, reinit, false, true)
    output
end

"""
```
throttle(dt, input, f=(acc,x)->x, init=value(input), reinit=x->x;
            typ=typeof(init), name=auto_name!(string("throttle ",dt,"s"), input), leading=false)
```

Throttle a signal to update at most once every dt seconds. By default, the throttled signal holds the last update of the `input` signal during each `dt` second time window.

This behavior can be changed by the `f`, `init` and `reinit` arguments. The `init` and `f` functions are similar to `init` and `f` in `foldp`. `reinit` is called when a new throttle time window opens to reinitialize the initial value for accumulation, it gets one argument, the previous accumulated value.

For example
    `y = throttle(0.2, x, push!, Int[], _->Int[])`
will create vectors of updates to the integer signal `x` which occur within 0.2 second time windows.

If `leading` is `true`, the first update from `input` will be sent immediately by the throttle signal. If it is false, the first update will happen `dt` seconds after `input`'s first update

New in v0.4.1: `throttle`'s behaviour from previous versions is now available with the `debounce` signal type.

"""
function throttle(dt, node::Signal{T}, f=(acc,x)->x, init=value(node),
        reinit=x->x; typ=typeof(init), name=auto_name!("throttle $(dt)s", node),
        leading=false) where T
    output = Signal(typ, init, (node,); name=name)
    throttle_connect(dt, output, node, f, init, reinit, leading, false)
    output
end

# Aggregate a signal producing an update at most once in dt seconds
function throttle_connect(dt, output, input, f, init, reinit, leading, debounce)
    collected = init
    timer = Timer(identity, interval=0) #dummy timer to initialise
    dopush(_) = begin
        push!(output, collected)
        collected = reinit(collected)
        prevpush = time()
    end

    # we add the do_throttle as a foreach on the input, so when input updates it
    # collects the input values and pushes to the output when the time is right.
    prevpush = 0 # immediate push of `input`'s first update (unless leading is false)
    function do_throttle(inpval)
        collected = f(collected, inpval)
        prevpush == 0 && !leading && (prevpush = time())
        elapsed = time() - prevpush
        debounce && (elapsed = 0) # for debounce, only the timer can trigger a push

        close(timer)
        if elapsed > dt
            # prevpush is reset in dopush, so that calls via the Timer also reset it
            dopush(elapsed)
        else
            timer = Timer(dopush, interval=dt-elapsed)
        end
        nothing
    end
    foreach(do_throttle, input; init=nothing, name="$(input.name) throttler")
end

"""
    every(dt)

A signal that updates every `dt` seconds to the current timestamp. Consider using `fpswhen` or `fps` if you want specify the timing signal by frequency, rather than delay.
"""
function every(dt; name=auto_name!("every $dt secs"))
    n = Signal(time(), (); name=name)
    every_connect(dt, n)
    n
end

function every_connect(dt, output)
    outputref = WeakRef(output)
    function onerror_close_timer(pushnode, val, error_node, ex)
        print_error(pushnode, val, error_node, ex)
        close(timer)
    end
    timer = Timer(x -> push!(outputref.value, time(), onerror_close_timer), dt; interval=dt)
    finalizer(_->close(timer), output)
    output
end

"""
    fpswhen(switch, rate)

returns a signal which when `switch` signal is true, updates `rate` times every second. If `rate` is not possible to attain because of slowness in computing dependent signal values, the signal will self adjust to provide the best possible rate.
"""
function fpswhen(switch, rate; name=auto_name!("$rate fpswhen", switch))
    # Creates a node and sets up a timer that pushes to the node every 1.0/rate
    # seconds.
    n = Signal(Float64, 0.0, (switch, ); name=name)
    fpswhen_connect(rate, switch, n, name)
    n
end

function setup_next_tick(outputref, switchref, dt, wait_dt)
    Timer(t -> begin
        if value(switchref.value)
            push!(outputref.value, dt)
        end
    end, interval=wait_dt)
end

function fpswhen_connect(rate, switch, output, name)
    prev_time = time()
    dt = 1.0/rate
    outputref = WeakRef(output)
    switchref = WeakRef(switch)
    timer = Timer(identity, interval=0) # dummy timer to initialise
    function fpswhen_runner()
        # this function will run if switch gets a new value (i.e. is "active")
        # and if output is pushed to (assumed to be by the timer)
        if switch.value
            start_time = time()
            timer = setup_next_tick(outputref, switchref, start_time-prev_time, dt)
            prev_time = start_time
        else
            close(timer)
        end
        switch.value
    end
    # the fpswhen_aux will start and stop the timer if switch's value updates, it'll
    # also setup the next tick once the first tick is pushed to output
    fpswhen_aux = Signal(switch.value, (switch, output); name="fpswhen runner switch: $(switch.name), output: $(output.name)")
    preserve(fpswhen_aux)
    add_action!(fpswhen_runner, fpswhen_aux)

    fpswhen_runner() # init
    # ensure timer stops when output node is garbage collected
    finalizer(_->close(timer), output)
end

"""
    fps(rate)

Same as `fpswhen(Input(true), rate)`
"""
fps(rate; name="$rate fps") = fpswhen(Signal(Bool, true, (); name="fps true"), rate; name=name)
