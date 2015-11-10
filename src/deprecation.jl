import Base: consume, foldl, call, @deprecate
export lift, consume, foldl, keepwhen, keepif, dropif, dropwhen

@deprecate lift(f, s::Signal...; kwargs...) map(f,s...; kwargs...)
@deprecate consume(f::Union{Function, DataType}, s::Signal...;kwargs...) map(f, s...;kwargs...)
@deprecate foldl(f, x, s::Signal...;kwargs...) foldp(f, x, s...;kwargs...)
@deprecate keepwhen filterwhen
@deprecate keepif filter
@deprecate dropif(f, default, signal) filter(x -> !f(x), default, signal)
@deprecate dropwhen(predicate, x, signal) filterwhen(map(!, predicate), x, signal)
@deprecate call{T}(::Type{Node{T}}, x) Input(T, x)
