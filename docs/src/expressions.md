# Peggy expresions

Use [`@peg`](@ref) to create a parser.  You can also use the underly constructor functions which
is occasionally useful.

All examples assume you have installed Peggy.jl and loaded the package with
```jldoctest peggy
julia> using Peggy
```

## End of string

Matches the end of the input string. Consumes nothing, returns `()`.

```jldoctest peggy
julia> ( END() )("")
()

julia> ( END() )("something")
ERROR: ParseException @ (no file):1:1
something
^
expected: END()
[...]
```
## String literal

Matches a literal string and returns the string.

```jldoctest peggy
julia>  (@peg { "hello" "Peggy" })( "hello Peggy!" )
("hello", "Peggy")
```

By default, trailing whitespace is ignored. You can alter this behavior with the lower-level `peggy` function:
You can change the default trailing whitespace:

```jldoctest peggy
julia> (@peg { peggy("a"; skiptrailing=r"") "b"  })( "a b" )
ERROR: ParseException @ (no file):1:2
a b
 ^
expected: "b"
[...]
```

## Repetition and Optionality

### N or more repitions

```jldoctest peggy
julia> ( @peg "a"*2 )( "aa" )
2-element Vector{String}:
 "a"
 "a"

julia> ( @peg "a"*2 )( "a" )
ERROR: ParseException @ (no file):1:2
a
 ^
expected: "a"
[...]
```

```jldoctest peggy
julia> (@peg { "a"*(1:2) })( "aaaab" ) 
2-element Vector{String}:
 "a"
 "a"

julia> (@peg { "a"*(1:2) })( "ab" ) 
1-element Vector{String}:
 "a"

julia> (@peg { "a"*(2:3) })( "ab" ) 
ERROR: ParseException @ (no file):1:2
ab
 ^
expected: "a"
[...]
```

Sugar:



## Sequence

```jldoctest peggy
julia> (@peg { "a"*_ "b" END() })( "aaab" ) 
(["a", "a", "a"], "b", ())
```
```jldoctest peggy
julia> (@peg { result="a"*_ "b" END() })( "aaab" ) 
3-element Vector{String}:
 "a"
 "a"
 "a"
```
```jldoctest peggy
julia> (@peg { as="a"*_ "b" END()  :> { length(as) }})( "aaab" ) 
3
```
```jldoctest peggy
julia> (@peg { as="a"*_ "b" END()  :> length })( "aaab" ) 
3
```
!!! warning "Squirrely Curly"
    Julia's parsing of curly-braces is mostly the same as for square-brackets.  But it has a strange interaction with unary
    operators.
```jldoctest
julia> Meta.show_sexpr(:( !{ a } ))
(:curly, :!, :a)
julia> Meta.show_sexpr(:( ![ a ] ))
(:call, :!, (:vect, :a))
```

Use parentheses to avoid problems:
```jldoctest
julia> Meta.show_sexpr(:( !({ a }) ))
(:call, :!, (:braces, :a))
```

## Character class

```jldoctest peggy
julia> ( @peg CHAR("[:alpha:]_")*0  )( "böse_7734!" )
5-element Vector{SubString{String}}:
 "b"
 "ö"
 "s"
 "e"
 "_"
```

## Regular Expressions

!!! note "Regular expressions can kill performance."

    By default, `r"[[:space:]*"` is translated to `Peggy.GeneralRegexParser("[[:space:]]*")` because Peggy
    assumes the expression can match an empty string.  That assumption may cause a rule to be deemed
    left-recursive, which has some overhead.  

    If you know your expression does not match "", you can use `Peggy.NonemptyRegx`.  
    For example, Peggy's PCRE class express `:["[:space]"]` expands to `Peggy.NonemptyRegex("[[:scpace]]").

## Peggy functions
