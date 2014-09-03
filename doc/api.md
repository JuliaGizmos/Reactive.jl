---
title: API
author: Shashi Gowda
order: 2
...

# Signals

## Signal{T}
{{{Signal}}}

```{.julia execute="false"}
abstract Signal{T}
```

## Input{T}
{{{Input}}}

```{.julia execute="false"}
type Input{T} <: Signal{T} ... end
i = Input(0)    # Construct an input signal of integers with the default value 0
```
## Node{T}
{{{Node}}}

```{.julia execute="false"}
abstract Node{T} <: Signal{T}
```

# Transforming signals

## lift
{{{lift}}}

### @lift
{{{@lift}}}

Example:
```{.julia execute="false"}
z = @lift x*y
```
Here when `x` and `y` are signals, the above expression is equivalent to:
```{.julia execute="false"}
z = lift((a,b) -> a*b, x, y)
```
If, say, only x is a signal, then it is equivalent to:

```{.julia execute="false"}
z = lift(a -> a*y, x)
```

You can also create signals of tuples or arrays:

```{.julia execute="false"}
# E.g.
z = @lift (x, 2y, x*y)
# z is now a Signal{Tuple}
```

# State

## foldl
{{{foldl}}}

## foldr
{{{foldr}}}

# Filters and Gates

## filter
{{{filter}}}

## dropif
{{{dropif}}}

## droprepeats
{{{droprepeats}}}

## keepwhen
{{{keepwhen}}}

## dropwhen
{{{dropwhen}}}

# Sample and Merge
## sampleon
{{{sampleon}}}

## merge
{{{merge}}}

# Timed Signals

## fps
{{{fps}}}

## fpswhen
{{{fpswhen}}}

## every
{{{every}}}

## timestamp
{{{timestamp}}}
