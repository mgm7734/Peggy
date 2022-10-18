```@meta
CurrentModule = Peggy
using Peggy
```
# Peggy

*Generate Packrat PEG parsers for Julia* 

Features:

- pretty good syntax error messages. 
- detects indirect left-recursive rules during compilation. Only left-recursive rules pay a performance cost
- both combinator functions and a macro are provided

A [`Peggy.Parser`](@ref) is function that takes a string as input and returns its parsed value.

Create parsers using either a succinct [`Peggy expression`](#peggy-expresions) via the [`@peg`](@ref) macro
or lower-level functions.

## Index
```@index
```

```@autodocs
Modules = [Peggy]
```
