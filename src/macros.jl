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
    if in(ex.head, [:call, :row, :vcat, :tuple, :cell1d, :(:)])
        ex.args = map(x->sub_val(x, m), ex.args)
    elseif ex.head == :kw
        ex.args[2] = sub_val(ex.args[2], m)
    end

    # This bit is required for things like sampleon(x, y) to be
    # turned into a single signal first and then used as input
    # to the expression being lifted.
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
    if in(ex.head, [:call, :row, :vcat, :tuple, :cell1d, :(:)])
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

# Convenience macro for calling `lift`. Evaluates an
# expression looking for signal values, and returns a
# signal whose values are that of the expression as the
# signals in it change.
#
# Args:
#    expr: Expression
macro lift(ex)
    ex = Expr(:quote, ex)
    esc(quote
        ex = Reactive.sub_val($ex, current_module())
        ex, sigs = Reactive.extract_signals(ex, current_module())
        args = Symbol[]
        vals = Any[]
        for (k, v) in sigs
            push!(args, v)
            push!(vals, k)
        end
        eval(current_module(),
             Expr(:call, :lift,
                  Expr(:->, Expr(:tuple, args...), ex),
                  vals...))
    end)
end
