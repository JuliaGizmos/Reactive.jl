const _node_finalizers = WeakKeyDict()

typealias Finalizer Union{Ptr, Function}

const _finalizer = Base.finalizer
finalizer(x::Node, f::Finalizer) = begin
    _node_finalizers[x] = push!(get(_node_finalizers,x,Any[]), f)
    # also add it to julia's finalizer
    invoke(_finalizer, (Any, Finalizer), x, f)
end

finalize(x::Node) = begin
    !haskey(_node_finalizers, x) && return
    for f in _node_finalizers[x]
        f(x)
    end
end 
