using Compat

export every, fps, fpswhen, throttle

# Aggregate a signal producing an update at most once in dt seconds
function throttle_connect(dt, output, input, f, init, reinit)
    let collected = init, timer = @compat Timer(x->x, 0)
        add_action!(input, output) do output, timestep
            collected = f(collected,  value(input))
            close(timer)
            timer = @compat Timer(x -> begin push!(output, collected); collected=reinit(collected) end, dt)
        end
    end
end

function throttle{T}(dt, node::Node{T}, f=(acc, x) -> x, init=value(node), reinit=x->x)
    output = Node(init)
    throttle_connect(dt, output, node, f, init, reinit)
    output
end

function every(dt)
    n = Node(time())
    every_connect(dt, n)
    n
end

function every_connect(dt, output)
    timer = @compat Timer(x -> push!(output, time()), dt, dt)
    finalizer(output, x -> close(timer))
    output
end

function fpswhen_connect(rate, switch, output)
    let prev_time = time(),
        dt = 1.0/rate # minimum dt

        for inp in [output, filter(x->x, false, switch)]
            add_action!(inp, output) do output, timestep
                start_time = time()
                value(switch) && @compat Timer(x -> begin
                    value(switch) && push!(output, time() - prev_time)
                end, dt)
                prev_time = start_time
            end
        end

        value(switch) &&
            @compat Timer(x -> value(switch) && push!(output, time() - prev_time), dt)
    end
end

function fpswhen(switch, rate)
    n = Node(Float64, 0.0)
    fpswhen_connect(rate, switch, n)
    n
end

fps(rate) = fpswhen(Node(true), rate)

