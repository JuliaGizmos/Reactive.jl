import Base: map, merge, filter

if isdefined(Base, :foreach)
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
       bindmap!,
       unbind!,
       bound_srcs,
       bound_dests

"""
    map(f, s::Signal...) -> signal

Transform signal `s` by applying `f` to each element. For multiple signal arguments, apply `f` elementwise.
"""
function map(
        f, input::Signal, inputsrest::Signal...;
        init = f(map(value, (input, inputsrest...))...),
        typ = typeof(init), name = auto_name!("map", input, inputsrest...)
    )
    n = Signal(typ, init, (input, inputsrest...); name = name)
    connect_map(f, n, input, inputsrest...)
    n
end

function connect_map(f, output, inputs...)
    add_action!(output) do
        set_value!(output, f(map(value, inputs)...))
    end
end

probe(node, name, io=stderr) =
    map(x -> println(io, name, " >! ", x), node)

"""
    foreach(f, inputs...)

Same as `map`, but will be prevented from gc until all the inputs have gone out of scope. Should be used in cases where `f` does a side-effect.
"""
foreach(f, in1::Signal, inputs::Signal...; kwargs...) = preserve(map(f, in1, inputs...; kwargs...))

"""
    filter(f, default, signal)

remove updates from the `signal` where `f` returns `false`. The filter will hold
the value default until f(value(signal)) returns true, when it will be updated
to value(signal).
"""
function filter(f::Function, default, input::Signal{T}; name=auto_name!("filter", input)) where T
    n = Signal(T, f(value(input)) ? value(input) : default, (input,); name=name)
    connect_filter(f, default, n, input)
    n
end

"""
    filter(f, signal)

remove updates from the `signal` where `f` returns `false`. The filter will hold
the current value of the signal until `f(value(signal))` returns true.
"""
filter(f::Function, input::Signal{T}; kwargs...) where {T} = filter(f, value(input), input; kwargs...)

function connect_filter(f, default, output, input)
    add_action!(output) do
        val = value(input)
        if f(val)
            set_value!(output, val)
        else
            deactivate!(output)
        end
    end
end

"""
    filterwhen(switch::Signal{Bool}, default, input)

Keep updates to `input` only when `switch` is true.

If switch is false initially, the specified default value is used.
"""
function filterwhen(predicate::Signal{Bool}, default, input::Signal{T};
                     name=auto_name!("filterwhen", predicate, input)) where T
    n = Signal(T, value(predicate) ? value(input) : default, (input,); name=name)
    connect_filterwhen(n, predicate, input)
    n
end

function connect_filterwhen(output, predicate, input)
    add_action!(output) do
        if value(predicate)
            set_value!(output, value(input))
        else
            deactivate!(output)
        end
    end
end

"""
    foldp(f, init, inputs...)

[Fold](http://en.wikipedia.org/wiki/Fold_(higher-order_function)) over past values.

Accumulate a value as the input signals change. `init` is the initial value of the accumulator.
`f` should take `1 + length(inputs)` arguments: the first is the current accumulated value and the rest are the current input signal values. `f` will be called when one or more of the `inputs` updates. It should return the next accumulated value.
"""
function foldp(f::Function, v0, input::Signal, inputsrest::Signal...;
        typ=typeof(v0), name=auto_name!("foldp", input, inputsrest...))
    n = Signal(typ, v0, (input, inputsrest...); name=name)
    connect_foldp(f, v0, n, (input, inputsrest...))
    n
end

function connect_foldp(f, v0, output, inputs)
    add_action!(output) do
        vals = map(value, inputs)
        set_value!(output, f(output.value, vals...))
    end
end

"""
    sampleon(a, b)

Sample the value of `b` whenever `a` updates.
"""
function sampleon(sample_trigger, input::Signal{T}; name=auto_name!("sampleon", input)) where T
    n = Signal(T, value(input), (sample_trigger,); name=name)
    connect_sampleon(n, input)
    n
end

function connect_sampleon(output, input)
    # this will only get run when sampler updates, as sample_trigger is output's
    # only parent
    add_action!(output) do
        set_value!(output, input.value)
    end
end

"""
    merge(inputs...)

Merge many signals into one. Returns a signal which updates when
any of the inputs update. If many signals update at the same time,
the value of the *youngest* (most recently created) input signal is taken.
"""
function merge(in1::Signal, inputs::Signal...; name=auto_name!("merge", in1, inputs...))
    ins = (in1, inputs...)
    youngestid = maximum(map(x->x.id, ins))
    youngest_val = nodes[youngestid].value
    n = Signal(typejoin(map(eltype, ins)...), value(youngest_val), ins; name=name)
    connect_merge(n, in1, inputs...)
    n
end

function connect_merge(output, inputs...)
    function merge_action()
        lastactive = getlastactive(output)
        lastactive != nothing && set_value!(output, value(lastactive))
        # we don't deactivate! on lastactive == nothing, since I suppose the push
        # should propagate even if some of the nodes died just after updating.
    end
    add_action!(merge_action, output)
end

"""
`getlastactive(merge_node)`
Search backwards in nodes, and return the first active node that is one
of merge_node's parents
"""
function getlastactive(merge_node)
    i = merge_node.id - 1
    while i > 0
        node = nodes[i].value
        if isactive(node) && node in merge_node.parents
            return node
        end
        i -= 1
    end
    # If parent nodes have all been GC'd, but there is still a reference to the
    # merge in user code, then none of the parents should have been active,
    # so the merge action shouldn't run, so we shouldn't have got here. However,
    # in the rare case that the node got GC'd after it was found to be an active
    # parent of the merge but before we got here, then I guess the merge node
    # shouldn't change value.
    return nothing
end

"""
    previous(input, default=value(input))

Create a signal which holds the previous value of `input`.
You can optionally specify a different initial value.
"""
function previous(input::Signal{T}, default=value(input); name=auto_name!("previous", input)) where T
    n = Signal(T, default, (input,); name=name)
    connect_previous(n, input)
    n
end

function connect_previous(output, input)
    prev_value = value(input)
    add_action!(output) do
        set_value!(output, prev_value)
        prev_value = value(input)
    end
end

"""
    delay(input, default=value(input))

Schedule an update to happen after the current update propagates
throughout the signal graph.

Returns the delayed signal.
"""
function delay(input::Signal{T}, default=value(input); name=auto_name!("delay", input)) where T
    n = Signal(T, default, (input,); name=name)
    connect_delay(n, input)
    n
end

function connect_delay(output, input)
    function push_delayed(inpval)
        # only push when input is active (avoids it pushing to itself endlessly)
        push!(output, inpval)
        nothing
    end
    foreach(push_delayed, input; init=nothing)
end

"""
    droprepeats(input)

Drop updates to `input` whenever the new value is the same
as the previous value of the signal.
"""
function droprepeats(input::Signal{T}; name=auto_name!("droprepeats", input)) where T
    n = Signal(T, value(input), (input,); name=name)
    connect_droprepeats(n, input)
    n
end

function connect_droprepeats(output, input)
    prev_value = value(input)
    add_action!(output) do
        if prev_value != value(input)
            set_value!(output, value(input))
            prev_value = value(input)
        else
            deactivate!(output)
        end
    end
end

"""
    flatten(input::Signal{Signal}; typ=Any)

Flatten a signal of signals into a signal which holds the
value of the current signal. The `typ` keyword argument specifies
the type of the flattened signal. It is `Any` by default.
"""
function flatten(input::Signal; typ=Any, name=auto_name!("flatten", input))
    n = Signal(typ, input.value.value, (input,); name=name)
    connect_flatten(n, input)
    n
end


"""
`connect_flatten(output, input)`

`output` is the flatten node, `input` is the Signal{Signal} ("sigsig") node. The
flatten needs to update on changes to the input sigsig, or changes to the value
of the current sig (`current_node`). The former is achieved through a foreach `wire_flatten`
attached to the input sigsig. The latter is achieved through binding the flatten
to `current_node`.
"""
function connect_flatten(output, input)
    # input is a Signal{Signal} (aka sigsig), current_node is the signal/node
    # that is the input's current value. wire_flatten will run when the sigsig gets a new signal as its
    # value. This ensures that set_flatten_val will be run (and flatten output
    # node's value will update) when either the current_node updates, or when
    # the input sigsig updates.
    current_node = input.value
    wire_flatten() = begin
        # If the sigsig's value has changed update output's parents so it will
        # only update when the new current_node updates, and no longer
        # update when the previous signal updates.
        if current_node != input.value
            unbind!(output, current_node, false)
            current_node = input.value
            bind!(output, current_node, false)
            # the bind will have run downstream actions - avoid doubling up
            deactivate!(output)
        end
    end

    add_action!(wire_flatten, output)
    bind!(output, current_node, false)
end

const _bindings = Dict() # XXX GC Issue? can't use WeakKeyDict with Pairs...
const _active_binds = Dict()

"""
    `bind!(dest, src, twoway=true; initial=true)`

for every update to `src` also update `dest` with the same value and, if
`twoway` is true, vice-versa. If `initial` is false, `dest` will only be updated
to `src`'s value when `src` next updates, otherwise (if `initial` is true) both
`dest` and `src` will take `src`'s value immediately.
"""
function bind!(dest::Signal, src::Signal, twoway=true; initial=true)
    dest2src = twoway ? identity : nothing
    bindmap!(dest, identity, src, dest2src)
end


"""
    `bindmap!(dest::Signal, src2dest::Function, src::Signal, dest2src=nothing; initial=true)`

for every update to `src` also update `dest` with a modified value (using the
function `src2dest`) and, if `dest2src` is specified, a two-way update will hold.
If `initial` is false, `dest` will only be updated to `src`'s modified value
when `src` next updates, otherwise (if `initial` is true) both `dest` and `src`
will take their respective modified values immediately.
"""
function bindmap!(dest::Signal, src2dest::Function, src::Signal, dest2src = nothing; initial = true)
    twoway = dest2src ≠ nothing
    if haskey(_bindings, src=>dest)
        # subsequent bind!(dest, src) after initial should be a no-op
        # though we should allow a change in preference for twoway bind.
        if twoway
            bindmap!(src, dest2src, dest, initial = initial)
        end
        return
    end

    # We don't set src as a parent of dest, since a
    # two-way bind would technically introduce a cycle into the signal graph,
    # and I suppose we'd prefer not to have that. Instead we just set dest as
    # active when src updates, which will allow its downstream actions to run.

    ordered_pair = src.id < dest.id ? src=>dest : dest=>src # ordered by id
    twoway && (_active_binds[ordered_pair] = false)
    # the binder action comes after dest, so dest's downstream actions
    # won't run unless we arrange it.
    function bind_updater(srcval)
        if !haskey(_bindings, src=>dest)
            # will happen if has been unbound but node not gc'd
            return
        end
        is_twoway = haskey(_active_binds, ordered_pair)
        if is_twoway && _active_binds[ordered_pair]
            # The _active_binds flag stops the (infinite) cycle of src
            # updating dest updating src ... in the case of a two-way bind
            _active_binds[ordered_pair] = false
        else
            is_twoway && (_active_binds[ordered_pair] = true)
            # we "pause" the current push!, simulate a push! to dest with
            # run_push then resume processing the original push by reactivating
            # the previously active nodes.
            active_nodes = pause_push()
            # `true` below is for dont_remove_dead nodes - messes with active_nodes
            # TODO - check that - not sure it actually does, this may be a relic
            # of an earlier implementation which used the node's id's
            run_push(dest, src2dest(src.value), onerror_rethrow, true) # here is the only place where we implement the modifying function!
            foreach(activate!, active_nodes)
        end
        nothing
    end
    finalizer(src) do src
        unbind!(dest, src, twoway)
    end
    _bindings[src=>dest] = map(bind_updater, src; name="binder: $(src.name)=>$(dest.name)")
    initial && bind_updater(src.value) # init now that _bindings[src=>dest] is set

    if twoway
        bindmap!(src, dest2src, dest, initial = initial)
    end

end

"""
    `unbind!(dest, src, twoway=true)`

remove a link set up using `bind!`
"""
function unbind!(dest::Signal, src::Signal, twoway=true)
    if !haskey(_bindings, src=>dest)
        return
    end

    _bindings[src=>dest] != nothing && close(_bindings[src=>dest])
    delete!(_bindings, src=>dest)

    ordered_pair = src.id < dest.id ? src=>dest : dest=>src # ordered by id
    haskey(_active_binds, ordered_pair) && delete!(_active_binds, ordered_pair)

    if twoway
        unbind!(src, dest, false)
    end
end

"""
Pause a push by recording the active nodes and setting them to inactive.
The push can be resumed by reactivating the nodes.
"""
function pause_push()
    active_nodes = WeakRef[]
    for noderef in nodes
        node = noderef.value
        if isactive(node)
            push!(active_nodes, WeakRef(node))
            deactivate!(node)
        end
    end
    active_nodes
end

"""
`bound_dests(src::Signal)` returns a vector of all signals that will update when
`src` updates, that were bound using `bind!(dest, src)`
"""
bound_dests(s::Signal) = [dest for (src, dest) in keys(_bindings) if src == s]

"""
`bound_srcs(dest::Signal)` returns a vector of all signals that will cause
an update to `dest` when they update, that were bound using `bind!(dest, src)`
"""
bound_srcs(s::Signal) = [src for (src, dest) in keys(_bindings) if dest == s]
