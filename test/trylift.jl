facts("trylift") do

    context("trylift") do

        x = Input(1)
        m = [1.0, 2.0, 3.1]

        y = trylift(i -> m[i], Int64, x)
        @fact eltype(y) => Reactive.Try{Int64}
        @fact value(y) => 1
        push!(x, 2)
        @fact value(y) => 2
        push!(x, 3)
        @fact value(y) => InexactError()
        push!(x, 4)
        if VERSION < v"0.4.0-dev+2374"
            @fact value(y) => BoundsError()
        else
            @fact value(y) => BoundsError(m,(4,))
        end
    end
end
