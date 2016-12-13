using PkgBenchmark
using Reactive

Reactive.stop()

@benchgroup "Signal creation" begin
    @bench "int" Signal(0)
    @bench "string" Signal($("x"))
    @bench "standalone update" (push!($(Signal(0)), 1); Reactive.run_till_now())
end

@benchgroup "map" begin
    x = Signal(0)
    y = map(-, x)
    @bench "2 node" (push!($x, 1); Reactive.run_till_now())

    z = map(+, x)

    @bench "3 nodes" (push!($x, 1); Reactive.run_till_now())

    a = map(+, x, y)
    @bench "4 nodes" (push!($x, 1); Reactive.run_till_now())
end
