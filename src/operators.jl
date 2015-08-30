import Base: map, merge, filter

export map,
       foreach,
       probe,
       filter, 
       dropif,
       foldp,
       sampleon,
       keepwhen,
       dropwhen,
       merge,
       previous,
       delay,
       boundcopy,
       droprepeats,
       flatten

function map(f, inputs::Node...;
             init=f(map(value, inputs)...), typ=typeof(init))

    n = Node(typ, init)
    connect_map(f, n, inputs...)
    n
end

function connect_map(f, output, inputs...)
    let prev_timestep = 0
        for inp in inputs
            add_action!(inp, output) do output, timestep
                if prev_timestep != timestep
                    result = f(map(value, inputs)...)
                    send_value!(output, result, timestep)
                    prev_timestep = timestep
                end
            end
        end
    end
end

foreach(f, inputs...; kwargs...) =
    preserve(map(f, inputs...; kwargs...))

probe(node, name, io=STDERR) =
    map(x -> println(io, name, " >! ", x), node)

function connect_filter(f, output, input)
    add_action!(input, output) do output, timestep
        val = value(input)
        f(val) && send_value!(output, val, timestep)
    end
end

function filter{T}(f::Function, default, input::Node{T})
    n = Node(T, default)
    connect_filter(f, n, input)
    n
end

dropif(f, default, node) = filter(x -> !f(x), default, node)


function connect_foldp(f, v0, output, input)
    let acc = v0
        add_action!(input, output) do output, timestep
            val = value(input)
            acc = f(acc, val)
            send_value!(output, acc, timestep)
        end
    end
end

function foldp(f::Function, v0, input; typ=typeof(v0))
    n = Node(typ, v0)
    connect_foldp(f, v0, n, input)
    n
end


function connect_sampleon(output, sampler, input)
    add_action!(sampler, output) do output, timestep
        send_value!(output, value(input), timestep)
    end
end

function sampleon{T}(sampler, input::Node{T})
    n = Node(T, value(input))
    connect_sampleon(n, sampler, input)
    n
end


function connect_keepwhen(output, predicate, input)
    add_action!(input, output) do output, timestep
        value(predicate) && send_value!(output, value(input), timestep)
    end
end

function keepwhen{T}(predicate::Node{Bool}, default, input::Node{T})
    n = Node(T, value(predicate) ? value(input) : default)
    connect_keepwhen(n, predicate, input)
    n
end

dropwhen(predicate, default, node) =
    keepwhen(map(!, predicate), default, node)

function connect_merge(output, inputs...)
    let prev_timestep = 0
        for inp in inputs
            add_action!(inp, output) do output, timestep
                # don't update twice in the same timestep
                if prev_timestep != timestep 
                    send_value!(output, value(inp), timestep)
                    prev_time = timestep
                end
            end
        end
    end
end

function merge(inputs...)
    @assert length(inputs) >= 1
    n = Node(typejoin(map(eltype, inputs)...), value(inputs[1]))
    connect_merge(n, inputs...)
    n
end

function previous{T}(input::Node{T}, default=value(input))
    n = Node(T, default)
    connect_previous(n, input)
    n
end

function connect_previous(output, input)
    let prev_value = value(input)
        add_action!(input, output) do output, timestep
            send_value!(output, prev_value, timestep)
            prev_value = value(input)
        end
    end
end

function delay{T}(input::Node{T}, default=value(input))
    n = Node(T, default)
    connect_delay(n, input)
    n
end

function connect_delay(output, input)
    add_action!(input, output) do output, timestep
        push!(output, value(input))
    end
end

function connect_bind(a, b)
    let current_timestep = 0
        add_action!(a, b) do b, timestep
            if current_timestep != timestep
                current_timestep = timestep
                send_value!(b, value(a), timestep)
            end
        end

        add_action!(b, a) do a, timestep
            if current_timestep != timestep
                current_timestep = timestep
                send_value!(a, value(b), timestep)
            end
        end
    end
end

function boundcopy{T}(input::Node{T})
    n = Node(T, value(input))
    bind_conn(n, input)
    n
end


function connect_droprepeats(output, input)
    let prev_value = value(input)
        add_action!(input, output) do output, timestep
            if prev_value != value(input)
                send_value!(output, value(input), timestep)
                prev_value = value(input)
            end
        end
    end
end

function droprepeats{T}(input::Node{T})
    n = Node(T, value(input))
    connect_droprepeats(n, input)
    n
end


function connect_flatten(output, input)
    let current_node = value(input),
        callback = (output, timestep) -> begin
            send_value!(output, value(current_node), timestep)
        end

        add_action!(callback, current_node, output)

        add_action!(input, output) do output, timestep

            # Move around action from previous node to current one
            remove_action!(callback, current_node, output)
            current_node = value(input)
            add_action!(callback, current_node, output)

            send_value!(output, value(current_node), timestep)
        end
    end
end

function flatten(input::Node; typ=Any)
    n = Node(typ, value(value(input)))
    connect_flatten(n, input)
    n
end
