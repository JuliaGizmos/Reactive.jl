v0.4.1
------
* Fix bugs in signal update ordering - see test/node_order.jl ("bfs bad", and "bfs bad, dfs bad") for examples fixed
* Fix for #123 changes the behaviour of `throttle`, for the old behaviour, use `debounce`
* Adds `bound_srcs(dest)`, and `bound_dests(src)` which return signals bound using `bind!(dest, src)`
* Performance improvements

v0.4.0
------
* API for `onerror` changed, see `?push!` for details`

v0.1.8
------
* Mix in Timing module into Reactive and remove it

