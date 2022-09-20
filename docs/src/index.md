```@meta
CurrentModule = Peggy
```
# Peggy

*Packrat parser combinators for Julia supporting left-recursive grammars.*

Features:


Pretty good error messages

- pretty good syntax error messages. [TODO: how costly is this? Make it optional?]
- detects and correctly handles left-recursion
- separation of syntax from functinality.  I'm still playing around with the input syntax.

## Quickstart
## Creating Parsers

Use [`@grammar`](@ref) to construct parsers.

```jldoctest
julia> using Peggy

julia> p = @grammar begin
          start = "match a"
       end;

julia> runpeg(p, "match abc") # does not need to match the entire string
"match a"

julia> p = @grammar begin
          start = [ a_or_bs " "... hexdigit !anych() ]
          a_or_bs = ("a" / "b")...
          hexdigit = anych("[:digit:]a-fA-F")
       end;

julia> p("abaab 9")
(a_or_bs = ["a", "b", "a", "a", "b"], hexdigit = "9")
```
## Index
```@index
```

```@autodocs
Modules = [Peggy]
```
