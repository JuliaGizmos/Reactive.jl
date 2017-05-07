using Reactive, GLAbstraction, GeometryTypes
import Reactive: edges, nodes
# Base.step() = Reactive.run(1)
Reactive.stop()

function test1(; use_async = true)
    # Reactive.run_async(use_async)
    a = Signal(0.0)

    b = map(/, a, Signal(23.0))
    c = map(/, a, Signal(8.0))
    f = foldp(+, 0.0, b)

    d = map(Vec3f0, b)
    e = map(Vec3f0, c)
    g = map(Vec3f0, f)

    m = map(translationmatrix, d)
    m2 = map(translationmatrix, e)

    m3 = map(*, m, m2)
    # I don't know why, but Mat*Vec is broken right now
    result = map(m3, g) do a, b
         r = a * Vec4f0(b, 1)
         Vec3f0(r[1], r[2], r[3])
    end
    total_time = 0.0

    # warm the cache
    push!(a, 0.1) # note causes the result to be slightly different, noticable for small N
    Reactive.run_till_now()
    println("post warmup, length(nodes): ", length(nodes))

    for i=1:N
        tic()
        push!(a, i)
        Reactive.run(1) # only needed for async
        total_time += toq()
    end

    @show(total_time)
    @show(total_time/N)
    value(result), total_time
end

function bf(a,c)
    a/c
end

function test2()
    total_time = 0.0
    a = 0.0
    accum = 0.0
    function ff(x)
        accum += x
    end
    local result
    for i=1:N
        tic()

        a = i
        b = bf(a, 23.0)
        c = bf(a, 8.0)
        f = ff(b)
        d = Vec3f0(b)
        e = Vec3f0(c)
        g = Vec3f0(f)

        m = translationmatrix(d)
        m2 = translationmatrix(e)

        m3 = m*m2
        r = m3 * Vec4f0(g, 1)
        result = Vec3f0(r[1], r[2], r[3])
        total_time += toq()
    end

    @show(total_time)
    @show(total_time/N)
    result, total_time
end

N = 10^6
react_res, react_time = test1(use_async=true)
regular_res, regular_time = test2()
@show react_res regular_res
react_time/regular_time
