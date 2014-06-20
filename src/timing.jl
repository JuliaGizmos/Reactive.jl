module Timing

using React

export every, fpswhen, fps, timestamp

function every(delta::Float64)
    i = Input(time())
    update(timer, status) = push!(i, time())
    t = Timer(update)
    start_timer(t, delta, delta)
    return lift(x->x, Float64, i) # prevent push!
end

function fpswhen(test::Signal{Bool}, delta::Float64)
    i = Input(time())
    update(timer, status) = if test.value push!(i, time()) end
    t = Timer(update)
    start_timer(t, delta, delta)
    return lift(x->x, Float64, i) # prevent push!
end

function fps(freq::Float64)
    return every(1/freq)
end

function timestamp{T}(s::Signal{T})
    return lift(x -> (time(), x), (Float64, T), s)
end

end # module
