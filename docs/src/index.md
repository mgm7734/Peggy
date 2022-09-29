```@meta
CurrentModule = Peggy
using Peggy
```
# Peggy

*Generate Packrat PEG parsers for Julia* 

Features:

- pretty good syntax error messages. 
- detects and correctly handles left-recursion
- both combinator functions and a macro are provided

## Creating Parsers

Use [`@peg`](@ref) to create a parser:  


```jldoctest
julia> using Peggy

julia> p = @peg("match a");

julia> p("match abc") # does not need to match the entire string
"match a"

julia> p = @peg begin
          start = { a_or_bs hexdigit !anych() }
          a_or_bs = ("a" || "b")*_
          hexdigit = :["[:digit:]a-fA-F"]
       end;

julia> p("abaab 9")
(a_or_bs = ["a", "b", "a", "a", "b"], hexdigit = "9")
```

## Peggy expresions

### String literals

```jldoctest
p = @peg "a string"

# output

p("a string")
"a string"
```
```jldoctest
julia> @peg("another string")("a string")
ERROR: ParseException @ (no file):1:1
a string
^
expected: "another string"
[...]
````
### Repetition and Optionality


### PCRE Character Classes

## Regular Expressions

!!! note "Regular expressions can kill performance."

    By default, `r"[[:space:]*"` is translated to `Peggy.GeneralRegexParser("[[:space:]]*")` because Peggy
    assumes the expression can match an empty string.  That assumption may cause a rule to be deemed
    left-recursive, which has some overhead.  

    If you know your expression does not match "", you can use `Peggy.NonemptyRegx`.  
    For example, Peggy's PCRE class express `:["[:space]"]` expands to `Peggy.NonemptyRegex("[[:scpace]]").

## Squirrely Curly

Julia's parsing of curly-braces is mostly the same as for square-brackets.  But it has a strange interaction with unary
operators.  
```
julia> Meta.show_sexpr(:( !{ a } ))
(:curly, :!, :a)
julia> Meta.show_sexpr(:( ![ a ] ))
(:call, :!, (:vect, :a))
```
## Index
```@index
```

```@autodocs
Modules = [Peggy]
```
