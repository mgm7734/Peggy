# Peggy expresions

Use [`@peg`](@ref) to create a parser.  You can also use the underly constructor functions which
is occasionally useful.

All examples assume you have installed Peggy.jl and loaded the package with
```jldoctest peggy
julia> using Peggy
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
expected: b
[...]
```

## Repetition and Optionality

### N or more repetitions

```jldoctest peggy
julia> ( @peg "a"*2 )( "aa" )
2-element Vector{SubString{String}}:
 "a"
 "a"

julia> ( @peg "a"*2 )( "a" )
ERROR: ParseException @ (no file):1:2
a
 ^
expected: a
[...]
```

#### Bounded repetitions

```jldoctest peggy
julia> (@peg { "a"*(1:2) })( "aaaab" ) 
2-element Vector{SubString{String}}:
 "a"
 "a"

julia> (@peg { "a"*(1:2) })( "ab" ) 
1-element Vector{SubString{String}}:
 "a"

julia> (@peg { "a"*(2:3) })( "ab" ) 
ERROR: ParseException @ (no file):1:2
ab
 ^
expected: a
[...]
```

### Sugar

```jldoctest peggy
julia> @peg({ x*_ }) == @peg({ x*0 })
true

julia> @peg({ x+_ }) == @peg({ x*1 })
true

julia> @peg(a*1) == @peg(a*(1:missing))
true

julia> (@peg { [ a ] }) == (@peg { a*(0:1) })
true
```


## Sequence

Yields a tuple of values.

```jldoctest peggy
julia> (@peg { "a"*_ "b" END() })( "aaab" ) 
(SubString{String}["a", "a", "a"], "b", ())
```

If any sequence item is named, only the named items are in the value.  If there is only
one value, it is returned directly rather than as a NTuple{1}

```jldoctest peggy
julia> (@peg { result="a"*_ "b" END() })( "aaab" ) 
3-element Vector{SubString{String}}:
 "a"
 "a"
 "a"
```

### Mapping

```jldoctest peggy
julia> (@peg { as="a"*_ "b" END()  :> { length(as) } })( "aaab" ) 
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
## Character class

```jldoctest peggy
julia> ( @peg CHAR("[:alpha:]_")*_  )( "böse_7734!" )
5-element Vector{SubString{String}}:
 "b"
 "ö"
 "s"
 "e"
 "_"
```


## Grammar

```jldoctest peggy
julia> g = @peg begin
       grammar = { rules=rule+_             :> { peggy(rules...) } }
       rule = { name "←" alts               :> { name => alts }}
       alts = { choice cs={ "/" choice }*_  :> { oneof(choice, cs...)} }
       choice = expr+_
       expr = {
            prim "*"                        :> { many(prim) }
            prim "+"                        :> { many(prim; min=1) }
            prim "?"                        :> { many(prim; max=1) }
            "&" expr                        :> { followedby(expr) }
            "!" expr                        :> { !expr }
            prim
       }
       prim = { 
            name !"←" 
            "[" charclass "]"               :> { CHAR(charclass) }
            "'" string "'"                  :> { peggy(string) }
            "(" alts ")"
            "."                             :> _ -> ANY()
       }
       name = { cs=CHAR("[:alpha:]_")+_ CHAR(raw"\s")*_     :> { *(cs...) } }
       charclass = {
            "-" ["]"] CHAR("^]")*_          :> t -> string(t[1], t[2]..., t[3]...)
            "]" CHAR("^]")*_                :> t -> string(t[1], t[2]...)
            CHAR("^]")+_                    :> t -> string(t...)
       }
       string = { ({ "''" :> _->"'" } | CHAR("^'"))*_  :> Base.splat(*) }
       end;
```

### Left recursion

## Not

## Lookahead

## Failure

```jldoctest peggy
julia> p = @peg begin
           cmd = { "say" word  :> { "You said: $word" } }
           word = { 
        !"FLA" cs=CHAR("[:alpha:]")+_  :> { *(cs...) } 
        "FLA" fail("don't say FLA")
           }
           end;

julia> p("say hello")
"You said: hello"

julia> p("say FLA")
ERROR: ParseException @ (no file):1:8
say FLA
       ^
expected: don't say FLA
[...]
```

## Regular Expressions

!!! note "Regular expressions can kill performance."

    By default, `r"[[:space:]*"` is translated to `Peggy.RegexParser("[[:space:]]*")` because Peggy
    assumes the expression can match an empty string.  That assumption may cause a rule to be deemed
    left-recursive, which has some overhead.  

    If you know your expression does not match "", you can use option `canmatchempty`.
    For example, Peggy's PCRE class express `:["[:space]"]` expands to `Peggy.RegexParser("[[:space]]"; canmatchempty=false).

