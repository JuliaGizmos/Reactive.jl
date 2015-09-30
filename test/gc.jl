using FactCheck
using Reactive

facts("gc checks") do
    # Ideally we need to test gc behavior for ALL operators
    # here we are only doing it for map as a test for the weakref logic
    x = Input(1)
    map(-, x)
    gc()

    # A dangling node should get gc'd
    @fact x.actions[end].recipient.value --> nothing
    # An intermediate node should not get gc'd until there is a reference to it.
    y = map(x -> 3x, map(x->2x, map(-, x)))
    gc()

    @fact x.actions[end].recipient.value --> not(nothing)
    push!(x, 1)
    
    Reactive.run(1)
    @fact value(y) --> -6

    # All intermediates should get gc'd if there is
    # no reference to the leaf
    foo(a) = map(b -> 3b, map(b->2b, map(-, a)))
    foo(x)
    gc()
    @fact x.actions[end].recipient.value --> nothing
end
