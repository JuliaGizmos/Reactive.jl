## Developer Notes

### Operators

Action updates the node whose `actions` Vector it's in with `set_value!` (pre-updates, should not run when node is pushed to, i.e. no parents active):
1. map (multiple parents)
1. filter (calls deactivate! when f(value(input)) is false)
1. filterwhen (calls deactivate! when value(input) is false)
1. foldp (single parent)
1. sampleon (sample trigger input is its only parent)
1. merge (multiple parents)
1. previous (caches the previous update)
1. droprepeats (calls deactivate! when value(input) == prev_value)
1. flatten (wire_flatten gets run whenever `input` sigsig updates. Uses `bind!` to update the flatten if the signal that is the `input` sigsig's current value (`current_node`) has its value updated).

Action on an auxilliary node connected to the input that pushes to it, this allows the action to run, even if the node is a non-input, but gets pushed to
1. throttle/debounce (the action is on a foreach on the input node, which sets up a timer to push to the throttle output node)
1. delay (the action is on a foreach on the input node, which just pushes to the delay node)
1. bind! (action is a `map` on the src node, which calls set_value! on the dest node, and returns nothing). e.g. from test/basics.jl "non-input bind":
```
s = Signal(1; name="sig 1")
m = map(x->2x, s; name="m")
s2 = Signal(3; name="sig 2")
push!(m, 10) # s,m,s2 should be 1, 10, 3

bind!(m, s2) # s,m,s2 should be 1, 3, 3

push!(m, 6) # s,m,s2 should be 1, 6, 6

push!(s2, 10) # s,m,s2 should be 1, 10, 10
```
1. fpswhen (the action to to set up the next tick/or stop the timer is on an auxilliary node with switch and the output node as the parents)

Other
1. every (doesn't actually have an action, just creates a timer to push to itself repeatedly)

### GC and Preserve

##### Docstring

`preserve(signal::Signal)`

prevents `signal` from being garbage collected (GC'd) as long as any of its `parents` are around. Useful for when you want to do some side effects in a signal.

e.g. `preserve(map(println, x))` - this will continue to print updates to x, until x goes out of scope. `foreach` is a shorthand for `map` with `preserve`.

##### Implementation

1. `preserve(x)` iterates through the parents of `x` and increases the count of `p.preservers[x]` by 1, and calls `preserve(p)` for each parent `p` of `x`.
1. Each signal has a field `preservers`, which is a `Dict{Signal, Int}`, which basically stores the number of times `preserve(x)` has been called on each of its child nodes `x`
1. Crucially, this Dict holds an active reference to `x` which stops it from getting GC'd
1. `unpreserve(x)` reduces the count of `preservers[x]` in all of x's parents, and if the count goes to 0, deletes the entry for (reference to) `x` in the `preservers` Dict thus freeing x for garbage collection.
1. Both `preserve` and `unpreserve` are also called recursively on all parents/ancestors of `x`, this means that all ancestors of x in the signal graph will be preserved, until their parents are GC'd or `unpreserve` is called the same number of times as `preserve` was called on them, or any of their descendants.
