using Reactive, Base.Test

@testset "CheckedSignal" begin
    @test_throws ArgumentError CheckedSignal(0, 1:2)
    @test_throws ArgumentError CheckedSignal(3, 1:2)
    @test_throws ArgumentError CheckedSignal(1, 2:3)
    @test value(CheckedSignal(2, 2:3)) == 2
    s = @inferred(CheckedSignal(1, 1:2))
    ms = map(x->x-100, s)
    @test value(ms) == -99
    push!(s, 2)
    step()
    @test value(s) == 2
    @test value(ms) == -98
    @test_throws ArgumentError push!(s, 3)
    @test_throws ArgumentError push!(s, 0)

    f(x) = contains(x, "red")
    s = CheckedSignal("Fred", f)
    @test value(s) == "Fred"
    push!(s, "credulous")
    step()
    @test value(s) == "credulous"
    @test_throws ArgumentError push!(s, "read")

    preserve(s)
    unpreserve(s)
end

nothing
