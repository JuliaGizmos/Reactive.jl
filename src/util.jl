function prev{T}(s::Signal{T}, first::T)
    lift(x -> x[1],
         foldl((a, b) -> (a[2], b), (first, s.value), s))
end

function prev(s::Signal)
    prev(s, s.value)
end

function dropif{T}(pred::Function, v0::T, s::Signal{T})
    filter(x->~pred(x), v0, s)
end

function keepwhen{T}(test::Signal{Bool}, v0::T, s::Signal{T})
    dropwhen(lift(x->~x, Bool, test), v0, s)
end
