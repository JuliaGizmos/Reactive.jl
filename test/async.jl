@testset "Async" begin

    @testset "async_map" begin
        x = Signal(1; name="x")
        t, y = async_map(-, 0, x)
        z = map(yv->2yv, y; name="z")

        @test (value(t)) == (nothing)
        @test (value(y)) == (0)
        @test (value(z)) == (0)

        push!(x, 2)
        step()
        step()

        @test (value(y)) == (-2)
        @test (value(z)) == (-4)
    end
end
