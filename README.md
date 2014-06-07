# React

[![Build Status](https://travis-ci.org/shashi/React.jl.png)](https://travis-ci.org/shashi/React.jl)

Reactive primitives for Julia.

This is heavily inspired by [Elm](http://elm-lang.org/)'s [Signal library](http://library.elm-lang.org/catalog/evancz-Elm/0.12/Signal)

## Installation

```julia
Pkg.clone("git://github.com/shashi/React.jl.git")
```

## Usage

```julia
using React

abstract Signal{T} # A signal is a time varying value
Input{T} <: Signal{T}  # An input signal -> root node in the signal graph
a = Input(0) # Create an input signal with default value 0
#=> <input{Int64}@1> 0

push!{T}(inp :: Input{T}, value :: T)
push!(a, 7) # Update the current value of signal a
#=> nothing
a
#=> <input{Int64}@1> 7

lift(output_type :: DataType, f :: Function, inputs :: Signal...)
b = lift(Int, x->x*x, a) # transform a to its square
#=> [lift{Int64}@2] 49
push!(a, 6)
#=> nothing
b
#=> [lift{Int64}@2] 36
c = lift(Int, +, a, b) # lift can combine more than one signals
#=> [lift{Int64}@3] 42

# Other methods
# reduce over a sequence of updates
reduce{T, U}(f :: Function, v0 :: T, signal :: Signal{U})

# merge two or more signals of the same type into one
# precedence goes to the earlier argument
merge{T}(signals :: Signal{T}...)

# drop updates based on a predicate, use v0 when initial value
# does not satisfy the predicate
filter{T}(pred :: Function, v0 :: T, signal :: Signal)

# drop updates with repeating values
droprepeats{T}(signal :: Signal{T})

# sampleon sample second signal whenever the first changes
sampleon{T, U}(s1 :: Signal{T}, s2 :: Signal{U})
```
