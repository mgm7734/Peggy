```@meta
CurrentModule = Peggy
```
# Peggy

*Packrat parser combinators for Julia supporting left-recursive grammars.*

Features:

- pretty good syntax error messages. [TODO: how costly is this? Make it optional?]
- detects and correctly handles left-recursion
- separation of syntax from functinality.  I'm still playing around with the input syntax.

## Quickstart
## Creating Parsers

Use [`@grammar`](@ref) to construct parsers.  It uses a slightly arcane syntax to avoid 
excessive punctuation while working with Julia's syntax. Julia's lack of suffix operators 
presented a particular challenge. Great advantage (abuse?) was taken of matrix notation.

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

## Regular Expressions

!!! note "Regular expressions can kill performance."

    By default, `r"[[:space:]*"` is translated to `Peggy.GeneralRegexParser("[[:space:]]*")` because Peggy
    assumes the expression can match an empty string.  That assumption may cause a rule to be deemed
    left-recursive, which has some overhead.  

    If you know your expression does not match "", you can use `Peggy.NonemptyRegx(r"[[:space]]")`.  
    That's what `:["[:space]"]` evalutes to.



Regular expressions can sometimes be convenient.  

However, they can kill performance.  Peggy doesn't analyze them and assumes that they may match an empty string.
This may cause rules to be erroneoulsy deemed left-recursive.

If you know your regex can never match an empty string, you can inform Peggy by using `TBD`.  This is what
already happens under the hood with `:[_PCRE-class_]` notation.

## Index
```@index
```

```@autodocs
Modules = [Peggy]
```
