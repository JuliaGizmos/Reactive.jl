import Base: consume, foldl, @deprecate
export lift, consume, foldl, keepwhen, keepif, dropif, dropwhen

@deprecate lift map
@deprecate consume(f::Union(Function, DataType), s::Signal...) map(f, s...)
@deprecate foldl(f, x, s::Signal...) foldp(f, x, s...)
@deprecate keepwhen filterwhen
@deprecate keepif filter
@deprecate dropif(f, default, signal) filter(x -> !f(x), default, signal)
@deprecate dropwhen(predicate, x, signal) filterwhen(map(!, predicate), x, signal)
