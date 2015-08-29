using Compat

export every, fps, fpswhen, debounce

function every(dt)
    n = Node(time())
    every_connect(dt, n)
    n
end

function every_connect(dt, output)
    timer = @compat Timer(x -> push!(output, time()), dt, dt)
    finalizer(output, x -> close(timer))
end


function fpswhen_connect(rate, switch, output)
    let prev_time = time(),
        dt = 1.0/rate # minimum dt

        for inp in [output, switch]
            add_action!(inp, output) do timestep
                start_time = time()
                value(switch) && @compat Timer(x -> push!(output, time() - prev_time), dt)
                prev_time = start_time
            end
        end

        @compat Timer(x -> push!(output, dt), dt)
    end
end

function fpswhen(switch, rate)
    n = Node(Float64, 0.0)
    fps_connect(rate, switch, n)
    n
end

function fps(rate)
    n = Node(Float64, 0.0)
    fpswhen_connect(rate, Node(true), n)
    n
end

function debounce_connect(dt, output, input)
    local timer
    add_action!(input, output) do timestep
        isdefined(:timer) && close(timer)
        timer = @compat Timer(x -> push!(output, value(input)), dt)
    end
end

# Produce an update at most once in dt seconds
function debounce{T}(dt, node::Node{T})
    output = Node{T}(value(node))
    debounce_connect(dt, output, node)
    output
end


