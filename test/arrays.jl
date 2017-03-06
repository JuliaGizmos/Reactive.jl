using Reactive, OffsetArrays
using Base.Test

@testset "Indices" begin
    @testset "Scalar indexing" begin
        A = reshape(1:3*4*2, 3, 4, 2)
        s = CheckedSignal(1, 1:2)
        V = view(A, :, :, s)
        @test V == reshape(1:12, 3, 4)
        push!(s, 2)
        step()
        @test V == reshape(13:24, 3, 4)
        @test freeze(V) == reshape(13:24, 3, 4)

        s = CheckedSignal(1, 1:3)
        @test_throws BoundsError view(A, :, :, s)

        V = view(A, s, :, :)
        @test V == A[1,:,:]
        push!(s, 3)
        step()
        @test V == A[3,:,:]

        V = view(A, :, s, :)
        @test V == A[:, 3, :]
    end

    @testset "Vector indexing" begin
        A = reshape(1:3*4*2, 3, 4, 2)
        s = CheckedSignal(1:4, 1:4)
        V = view(A, :, s, :)
        @test V == A
        push!(s, 2:3)
        step()
        @test V == A[:, 2:3, :]
    end

    @testset "Offset indexing" begin
        A = OffsetArray(reshape(1:3*4*2, 3, 4, 2), 1:3, 1:4, 1:2)
        s = CheckedSignal(OffsetArray(1:4, 1:4), 1:4)
        V = view(A, :, s, :)
        @test V == A
        push!(s, OffsetArray(2:3, 2:3))
        step()
        @test indices(V) === (1:3, 2:3, 1:2)
        @test V == A[:, OffsetArray(2:3, 2:3), :]
    end
end

nothing
