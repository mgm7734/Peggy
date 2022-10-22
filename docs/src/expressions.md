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

By default, surroundq whitespace is ignored. You can alter this behavior with the lower-level `peggy` function:

```jldoctest peggy
julia> (@peg { peggy("a"; whitespace=r"") "b"  })( " ab" )
ERROR: ParseException @ (no file):1:1
 ab
^
expected: "a"
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
expected: "a"
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
expected: "a"
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

Each sequence items has a name.  Grammar references are already a name.  Other types of items are givent the default name "_", but a different name can be assigned with `=`.

Items with names that start with "_" are discared.   If only one item remains, its value becomes the value of the sequence.
Otherwise the value is a tuple of the named item values.

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
julia> ( CHAR("[:alpha:]_")*0  )( "böse_7734!" )
5-element Vector{SubString{String}}:
 "b"
 "ö"
 "s"
 "e"
 "_"

julia> ( @peg( CHAR["[:alpha:]"]*_ ) )("ok")
2-element Vector{SubString{String}}:
 "o"
 "k"
```


## Grammar

Here's the PEG syntax from wikipedia's [Parsing expression grammar](https://en.wikipedia.org/wiki/Parsing_expression_grammar) article:

```jldoctest peggy
julia> wikisyntax = @peg begin
       grammar = { rules=rule+_             :> { grammar(rules...) } }
       rule = { name "←" expr               :> { name => expr }}
       expr = { alt as={ "/" alt }*_        :> { oneof(alt, as...)} }
       alt =  { is=item+_                   :> { peggy(is...) } }
       item = {
            prim "*"                        :> { many(prim) }
            prim "+"                        :> { many(prim; min=1) }
            prim "?"                        :> { many(prim; max=1) }
            "&" prim                        :> { followedby(prim) }
            "!" item                        :> { !item }
            prim
       }
       prim = { 
            name !"←" 
            "[" charclass "]"               :> { CHAR(charclass) }
            "'" string "'"                  :> { peggy(string) }
            "(" expr ")" 
            "."                             :> _ -> ANY()
       }
       name = { cs=CHAR("[:alpha:]_")+_ CHAR(raw"\s")*_     :> { Symbol(cs...) } }
       charclass = {
            "-" [ "]" ] CHAR("^]")*_        :> t -> string(t[1], t[2]..., t[3]...)
            "]" CHAR("^]")*_                :> t -> string(t[1], t[2]...)
            CHAR("^]")+_                    :> t -> string(t...)
       }
       string = { ({ "''" :> _->"'" } | CHAR("^'"))*_  :> Base.splat(*) }
       end;
```

Here's the non-CFG example that matches aⁿbⁿcⁿ:

```jldoctest peggy
julia> S = wikisyntax("""
       S ← &(A 'c') 'a'+ B !.
       A ← 'a' A? 'b'
       B ← 'b' B? 'c'
       """)
@peg(begin
  A={ "a" [A] "b" }
  B={ "b" [B] "c" }
  S={ followedby({ A "c" }) "a"+_ B END() }
end)
```

```jldoctest peggy
julia> S("aabbc")
ERROR: ParseException @ (no file):1:6
aabbc
     ^
expected: "c"
[...]
```

### Left recursion

## Not

## Lookahead

[`followedby`](@ref)

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

