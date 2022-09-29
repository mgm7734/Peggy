"""
    grammar([start::Symbol], (symbol => peg_expr)...)

Create a parser from a set of productions, which are named, mutually recursive parsers.  

Parsers that are members of a grammar can reference are member parser by their symbol.

If `start` is omitted, the symbol of the first production is used.
"""
function grammar(start::Symbol, production::Pair{Symbol}...) 
    Grammar(GramRef(start), Dict(s => parser(x) for (s,x) in production))
end
grammar(rules::Pair{Symbol}...) = grammar(first(rules).first, rules...)

"""
    pegparser(peg_expr)

Create a `Parser` from a PEG expression.


#  PEG Expressions

    - `String` - matches & yields the string literal
    - `Regex` - matches the  `Regex` and yields the match value
    - `Symbol` - matches to expression associated with the symbol in a `grammar`.
    - `[peg_expr...]` - matches the each expression in sequence. Yield a tuple of the result
    - `peg_exr...` - short-hand for the above, where syntatically valid.
    - `peg_expr => callable` - matches `peg_expr` and yields result of applying `callable` to its value.
    - `peg_epxr => k` - short-hand for `peg_expr` => _ -> k`
    - `Parser` - the result of `onoeof`, etc.

# See also

Any PEG parser is also a valid PEG expression There are a few other combinators that generate PEG parsers.

    - [`oneof(peg_expr...)`](@ref) - yields value of the first matching `peg_epxr`
    - [`many(peg_expr)`](@ref) - matches zero or more, yields a `AbstractVector` of the results
    - [`not(peg_expr)`](@ref) - matches only if `peg_epxr` fails. Yields `()`
"""
pegparser(s::AbstractString) = Literal(s)
pegparser(re::Regex) = GeneralRegexParser(re)
pegparser(s::Symbol) = GramRef(s)
pegparser(v::AbstractVector) = Sequence(map(pegparser, v))
function pegparser(pair::Pair) 
    (p, v) = pair
    fn = if (!isa(v, Function) && isempty(methods(v)))
        fn = _ -> v
    else
        v
    end
    Map(fn, pegparser(p))
end
pegparser(p::Parser) = p
pegparser(p1, p2, ps...) = pegparser([p1, p2, ps...])

"""
    anych(charclass::String)

Create a parser for a single character matchng regex character classes. 

Functionally identical to Regex("[\$charclass]") except it is known to never match an
empty string.  This is important to avoid unneccesary and expensive left-recursion
overhead.

# Examples

```jldoctet
julia> g = @grammar begin
       number = [ digit ds:(digit...)  { parse(Int, *(digit, ds...)) } ]
       digit = anych("[:digit:]")
       end;

julia> g("1234")
1234
```

"""
function anych(charclass::String) 
    try 
        NonemptyRegex(Regex("[$charclass]"))
    catch ex
        error("Invalid characer class \"$charclass\" ($( ex.msg ))")
        print(e)
    end
end

"""
A parser that matches any single character.
"""
anych() = NonemptyRegex(r".")

"""
    oneof(pegexpr...)

Create a parser for ordered alternatives.
"""
oneof(pegexpr...) = OneOf(map(pegparser, pegexpr))

"""
    many(pegexpr...)

Create a parser that matches zero or more repititions of `parser(pegexpr)`; return a vector of results.
"""
many(pegexpr...) = Many(pegparser(pegexpr...),0,missing)

"""
    not(p)

Create a parser that fails if parser `p` succeeds. Otherwise it succeeds with value `()`
"""
not(p) = Not(pegparser(p))

#Base.@deprecate parser pegparser
parser(x...) = pegparser(x...)

"""
A PEG parser that matches any character and yields it as a string.
"""
ANY = NonemptyRegex(r".")

"""
A PEG parser that matches the end of the input; yields result `()`.
"""
END = not(ANY)

