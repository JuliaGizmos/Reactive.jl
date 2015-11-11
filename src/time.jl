export every, fps, fpswhen, throttle

# Aggregate a signal producing an update at most once in dt seconds
function throttle_connect(dt, output, input, f, init, reinit)
    let collected = init, timer = Timer(x->x, 0)
        add_action!(input, output) do output, timestep
            collected = f(collected,  value(input))
            close(timer)
            timer = Timer(x -> begin push!(output, collected); collected=reinit(collected) end, dt)
        end
    end
end

function throttle{T}(dt, node::Node{T}, f=(acc, x) -> x, init=value(node), reinit=x->x)
    output = Node(init, (node,))
    throttle_connect(dt, output, node, f, init, reinit)
    output
end

function every(dt)
    n = Node(time(), ())
    every_connect(dt, n)
    n
end

function weakrefdo(ref, yes, no=()->nothing)
    ref.value != nothing ? yes(ref.value) : no()
end

function every_connect(dt, output)
    outputref = WeakRef(output)
    timer = Timer(x -> weakrefdo(outputref, x->push!(x, time()), ()->close(timer)), dt, dt)
    finalizer(output, _->close(timer))
    output
end

function setup_next_tick(outputref, switchref, dt, wait_dt)
    weakrefdo(switchref, value, ()->false) && Timer(t -> begin
        weakrefdo(switchref, value, ()->false) &&
            weakrefdo(outputref, x -> push!(x, dt))
    end, wait_dt)
end

function fpswhen_connect(rate, switch, output)
    let prev_time = time(),
        dt = 1.0/rate,
        outputref = WeakRef(output)
        switchref = WeakRef(switch)
        switch_ticks = filter(x->x, false, switch) # only turn-ons


        for inp in [output, switch_ticks]
            add_action!(inp, output) do output, timestep
                start_time = time()
                setup_next_tick(outputref, switchref, time()-prev_time, dt)
                prev_time = start_time
            end
        end

        setup_next_tick(outputref, switchref, dt, dt)
    end
end

function fpswhen(switch, rate)
    n = Node(Float64, 0.0, (switch,))
    fpswhen_connect(rate, switch, n)
    n
end

fps(rate) = fpswhen(Node(Bool, true, ()), rate)

