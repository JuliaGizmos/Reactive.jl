module Timing

using React

export every, fpswhen, fps, timestamp

# Guarrantees interval
function every(delta::Float64)
    i = Input(time())
    update(timer, status) = push!(i, time())
    t = Timer(update)
    start_timer(t, delta, delta)
    return lift(x->x, Float64, i) # prevent push!
end

# Try to get to freq number of FPS.
function fpswhen(test::Signal{Bool}, freq::Float64)
    diff = Input(0.0)

    local delta = 1/freq, t0 = time(),
          isOn = test.value, wasOn = false

    function update(timer, status)
        t = time()
        push!(diff, t-t0)
        t0 = t
    end

    local timer = Timer(update)
    function gate(isOn, t)
        if isOn
            if !wasOn t0 = time() end # a restart
            start_timer(timer, delta, 0)
        elseif wasOn
            stop_timer(timer)
        end
        wasOn = isOn
        return t
    end

    return lift(gate, Float64, test, diff)
end

function fps(freq::Float64)
    return fpswhen(Input(true), freq)
end

function timestamp{T}(s::Signal{T})
    return lift(x -> (time(), x), (Float64, T), s)
end

end # module
