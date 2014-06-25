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

# Timing

Timing functions are available in the React.Timing module:
```julia
using React.Timing
```

## fps
{{{fps}}}

## fpswhen
{{{fpswhen}}}

## every
{{{every}}}

## timestamp
{{{timestamp}}}
