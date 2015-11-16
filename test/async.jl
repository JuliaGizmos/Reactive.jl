
facts("Async") do

    context("async_map") do
        x = Signal(1)
        t, y = async_map(-, 0, x)

        @fact value(t) --> nothing
        @fact value(y) --> 0

        push!(x, 2)
        step()
        step()

        @fact value(y) --> -2
    end
end
