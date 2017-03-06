# Use Signals as indices for arrays

export freeze

using Base: ViewIndex, tail, to_indexes, to_index, index_shape
typealias RangeCheckedSignal{T,B<:Range} CheckedSignal{T,B}

##### Array overrides #####

Base.to_index(s::CheckedSignal) = to_index(value(s))

function Base.view{T,N}(A::AbstractArray{T,N}, I::Vararg{Union{ViewIndex,RangeCheckedSignal},N})
    B = map(bounds, I)
    checkbounds(A, B...)
    J = to_indexes(I...)
    SubArray(A, I, map(length, index_shape(A, J...)))
end

@inline function Base._indices_sub(S::SubArray, pinds, s::RangeCheckedSignal, I...)
    i = to_index(s)
    Base._indices_sub(S, pinds, i, I...)
end

@inline Base.reindex(V, idxs::Tuple{RangeCheckedSignal, Vararg{Any}}, subidxs::Tuple{Vararg{Any}}) =
    Base.reindex(V, (to_index(idxs[1]), tail(idxs)...), subidxs)

"""
    freeze(V::SubArray) -> Vnew

Return a new SubArray equivalent to `V` at the time of the `freeze`
call. If `V` has `Signal` indices, they will be converted to static
indices. `Vnew` can be useful if you need to ensure that
signal-indices won't update in the middle of some operation that
`yield`s.
"""
@inline freeze(V::SubArray) = view(parent(V), Base.to_indexes(V.indexes...)...)
