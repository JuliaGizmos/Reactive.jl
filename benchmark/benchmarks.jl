using PkgBenchmark
using Reactive

Reactive.stop()

@benchgroup "Signal creation" begin
    @bench "int" Signal(0)
    @bench "string" Signal($("x"))
    @bench "standalone update" (push!($(Signal(0)), 1); Reactive.run_till_now())
end

@benchgroup "map 1" begin
    x = Signal(0)
    y = map(-, x)
    @bench "2 node" (push!($x, 1); Reactive.run_till_now())

    z = map(+, x)

    @bench "3 nodes" (push!($x, 1); Reactive.run_till_now())

    a = map(+, x, y)
    @bench "4 nodes" (push!($x, 1); Reactive.run_till_now())
end

@benchgroup "map 2" begin
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
    @bench "10 nodes" (push!($x, 1); Reactive.run_till_now())
end
