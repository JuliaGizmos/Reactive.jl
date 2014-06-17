# return a list of symbols in expr that f applies to.
function find_applicable(ex::Expr, f::Function)
    unique(find_applicable!(Symbol[], current_module(), ex, f))
end

find_applicable!(L::Vector{Symbol}, M::Module, ex, f::Function) = L
function find_applicable!(L::Vector{Symbol}, M::Module, ex::Symbol, f::Function)
    isdefined(M, ex) && applicable(f, eval(M, ex)) ? push!(L, ex) : L
end   
function find_applicable!(L::Vector{Symbol}, M::Module, ex::Expr, f::Function)
    if ex.head == :call
        for arg in ex.args
            find_applicable!(L, M, arg, f)
        end
    end
    L
end

macro lift(ex)
    S = find_applicable(ex, signal)
    Expr(:call, :lift, 
         Expr(:->, Expr(:tuple, S...), ex),
    esc(S...))
end
