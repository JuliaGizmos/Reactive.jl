# evaluate as much of an expression as you can
function sub_val(x, m::Module)
    try
        eval(m, x)
    catch MethodError e
        return x
    end
end

sub_val(x::Symbol, m::Module) = eval(m, x)

function sub_val(ex::Expr, m::Module)
    if in(ex.head, [:call, :row, :vcat, :tuple, :cell1d])
        ex.args = map(x->sub_val(x, m), ex.args)
    elseif ex.head == :kw
        ex.args[2] = sub_val(ex.args[2], m)
    end
    if ex.head == :call
        try
            eval(m, ex)
        catch MethodError e
            return ex
        end
    else
        return ex
    end
end

function extract_signals!(ex, m::Module, dict::Dict{Any, Symbol})
    if applicable(signal, ex)
       if haskey(dict, signal(ex))
           return dict[signal(ex)]
       else
           sym = gensym()
           dict[signal(ex)] = sym
           return sym
       end
    else
        return ex
    end
end

function extract_signals!(ex::Expr, m::Module, dict::Dict{Any, Symbol})
    if in(ex.head, [:call, :row, :vcat, :tuple, :cell1d])
        ex.args = map(x->extract_signals!(x, m, dict), ex.args)
    elseif ex.head == :kw
        ex.args[2] = extract_signals!(ex.args[2], m, dict)
    end
    ex
end

function extract_signals(ex, m::Module)
    dict = Dict{Any, Symbol}()
    ex = extract_signals!(ex, m, dict)
    return ex, dict
end

# Convenience macro for calling `lift`
# Usage:
#    @lift expr
# expression is evaluated as much as possible and
# signal values in the expression are replaced with
# variables which will then get their values form the
# signals through a call to [`lift`](#lift) function.
macro lift(ex)
    ex = sub_val(ex, current_module())
    ex, sigs = extract_signals(ex, current_module())
    args = Symbol[]
    vals = Any[]
    for (k, v) in sigs
        push!(args, v)
        push!(vals, k)
    end
    Expr(:call, :lift,
         Expr(:->, Expr(:tuple, args...), ex),
         vals...)
end
