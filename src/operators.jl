import Base: map, merge, filter

if VERSION >= v"0.5.0-dev"
    import Base.foreach
end

export map,
       probe,
       filter, 
       filterwhen,
       foldp,
       sampleon,
       merge,
       previous,
       delay,
       droprepeats,
       flatten,
       bind!,
       unbind!

"""
    map(f, s::Signal...) -> signal

Transform signal `s` by applying `f` to each element. For multiple signal arguments, apply `f` elementwise.
"""
function map(f, input::Signal, inputsrest::Signal...;
             init=f(map(value, (input,inputsrest...))...), typ=typeof(init))

    n = Signal(typ, init, (input,inputsrest...))
    connect_map(f, n, input, inputsrest...)
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

probe(node, name, io=STDERR) =
    map(x -> println(io, name, " >! ", x), node)

"""
    foreach(f, inputs...)

Same as `map`, but will be prevented from gc until all the inputs have gone out of scope. Should be used in cases where `f` does a side-effect.
"""
foreach(f, inputs::Signal...) = preserve(map(f, inputs...))

"""
    filter(f, signal)

remove updates from the signal where `f` returns `false`.
"""
function filter{T}(f::Function, default, input::Signal{T})
    n = Signal(T, f(value(input)) ? value(input) : default, (input,))
    connect_filter(f, default, n, input)
    n
end

function connect_filter(f, default, output, input)
    add_action!(input, output) do output, timestep
        val = value(input)
        f(val) && send_value!(output, val, timestep)
    end
end

"""
    filterwhen(switch::Signal{Bool}, default, input)

Keep updates to `input` only when `switch` is true.

If switch is false initially, the specified default value is used.
"""
function filterwhen{T}(predicate::Signal{Bool}, default, input::Signal{T})
    n = Signal(T, value(predicate) ? value(input) : default, (input,))
    connect_filterwhen(n, predicate, input)
    n
end

function connect_filterwhen(output, predicate, input)
    add_action!(input, output) do output, timestep
        value(predicate) && send_value!(output, value(input), timestep)
    end
end

"""
    foldp(f, init, input)

[Fold](http://en.wikipedia.org/wiki/Fold_(higher-order_function)) over past values.

Accumulate a value as the `input` signal changes. `init` is the initial value of the accumulator.
`f` should take 2 arguments: the current accumulated value and the current update, and result in the next accumulated value.
"""
function foldp(f::Function, v0, inputs...; typ=typeof(v0))
    n = Signal(typ, v0, inputs)
    connect_foldp(f, v0, n, inputs)
    n
end

function connect_foldp(f, v0, output, inputs)
    let acc = v0
        for inp in inputs
            add_action!(inp, output) do output, timestep
                vals = map(value, inputs)
                acc = f(acc, vals...)
                send_value!(output, acc, timestep)
            end
        end
    end
end

"""
    sampleon(a, b)

Sample the value of `b` whenever `a` updates.
"""
function sampleon{T}(sampler, input::Signal{T})
    n = Signal(T, value(input), (sampler, input))
    connect_sampleon(n, sampler, input)
    n
end

function connect_sampleon(output, sampler, input)
    add_action!(sampler, output) do output, timestep
        send_value!(output, value(input), timestep)
    end
end


"""
    merge(input...)

Merge many signals into one. Returns a signal which updates when
any of the inputs update. If many signals update at the same time,
the value of the *youngest* input signal is taken.
"""
function merge(inputs...)
    @assert length(inputs) >= 1
    n = Signal(typejoin(map(eltype, inputs)...), value(inputs[1]), inputs)
    connect_merge(n, inputs...)
    n
end

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

"""
    previous(input, default=value(input))

Create a signal which holds the previous value of `input`.
You can optionally specify a different initial value.
"""
function previous{T}(input::Signal{T}, default=value(input))
    n = Signal(T, default, (input,))
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

"""
    delay(input, default=value(input))

Schedule an update to happen after the current update propagates
throughout the signal graph.

Returns the delayed signal.
"""
function delay{T}(input::Signal{T}, default=value(input))
    n = Signal(T, default, (input,))
    connect_delay(n, input)
    n
end

function connect_delay(output, input)
    add_action!(input, output) do output, timestep
        push!(output, value(input))
    end
end

"""
    droprepeats(input)

Drop updates to `input` whenever the new value is the same
as the previous value of the signal.
"""
function droprepeats{T}(input::Signal{T})
    n = Signal(T, value(input), (input,))
    connect_droprepeats(n, input)
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

"""
    flatten(input::Signal{Signal}; typ=Any)

Flatten a signal of signals into a signal which holds the
value of the current signal. The `typ` keyword argument specifies
the type of the flattened signal. It is `Any` by default.
"""
function flatten(input::Signal; typ=Any)
    n = Signal(typ, value(value(input)), (input,))
    connect_flatten(n, input)
    n
end

function connect_flatten(output, input)
    let current_node = value(input),
        callback = (output, timestep) -> begin
            send_value!(output, value(value(input)), timestep)
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

const _bindings = Dict()

"""
    bind!(a,b,twoway=true)

for every update to `a` also update `b` with the same value and vice-versa.
To only bind updates from b to a, pass in a third argument as `false`
"""
function bind!(a::Signal, b::Signal, twoway=true)

    let current_timestep = 0
        action = add_action!(b, a) do a, timestep
            if current_timestep != timestep
                current_timestep = timestep
                send_value!(a, value(b), timestep)
            end
        end
        _bindings[a=>b] = action
    end

    if twoway
        bind!(b, a, false)
    end
end

"""
    unbind!(a,b,twoway=true)

remove a link set up using `bind!`
"""
function unbind!(a::Signal, b::Signal, twoway=true)
    if !haskey(_bindings, a=>b)
        return
    end

    action = _bindings[a=>b]
    a.actions = filter(x->x!=action, a.actions)
    delete!(_bindings, a=>b)

    if twoway
        unbind!(b, a, false)
    end
end
