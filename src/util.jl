function prev{T}(s::Signal{T}, first::T)
    lift(x -> x[1],
         foldl((a, b) -> (a[2], b), (first, s.value), s))
end

function prev(s::Signal)
    prev(s, s.value)
end

# Drop updates if the predicate is true. Complement of filter.
#
# Args:
#     pred: a predicate function
#     v0:   base value to be used if the predicate is satisfied initially
#     s:    the signal to drop updates on
# Returns:
#     a filtered signal
function dropif{T}(pred::Function, v0::T, s::Signal{T})
    filter(x->!pred(x), v0, s)
end

# Keep only updates to the second signal only when the first signal is true.
# Complements dropwhen.
#
# Args:
#     test: a Signal{Bool} which tells when to keep updates to s
#     v0:   base value to use if the signal is false initially
#     s:    the signal to filter
# Returns:
#     a signal which updates only when the test signal is true
function keepwhen{T}(test::Signal{Bool}, v0::T, s::Signal{T})
    dropwhen(lift(x->~x, Bool, test), v0, s)
end
