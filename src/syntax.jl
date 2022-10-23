
"""
    peggy(expr...; whitespace=r"[[:space:]]*")

Create a `Parser` from a PEG expression.

The parser matches each expr sequentiallly and returns the combined results (details below).

Each expr can be one of the following.

 - `String` - matches & yields the string literal
 - `Regex` - matches the `Regex` and yields the match value (but avoid this)
 - `Symbol` - matches to expression associated with the symbol in a [`grammar`](@ref).
 - `Symbol => expr` - matches `expr` and assign it a name. 
 - `expr => callable` - matches `expr` and yields result of applying `callable` to its value.
 - `expr => k` - short-hand for `expr` => _ -> k`
 - `(expr, exprs...)` - same as `peggy(expr, exprs...)`
 - `[expr, exprs...]` - same as [`many(expr, exprs; max=1)`](@ref)
 - `Parser` - any expression that yields a parser

# Names and sequence results

Each element of a sequence has a name.  `Symbol` and `Symbol => expr` take the name of the symbol. All other
expressions are named ":_". The value of the sequence is then formed as follows.

Discard values with names starting with "_" if there are any that do not. 
If a single value remains, that is the sequence value.
Othewise the value is a `Vector` of the remaining values.

# Whitespace

String literals by default ignore surrounding whitespace.  Use option `whitespace=r""` to disable this.
"""
peggy(p::Parser) = p
peggy(s::AbstractString; whitespace=r"[[:space:]]*") = 
    RegexParser(Regex("\\Q$s\\E"); canmatchempty=(length(s) == 0), whitespace, pretty=sprint(show, s))
peggy(r::Regex) = RegexParser(r)
peggy(item1, item2, items...) = NamedSequence([item1, item2, items...])
peggy(es::Vector) = many(es...; max=1)
peggy(items::Tuple) = NamedSequence(collect(items))
peggy(s::Symbol) = GramRef(s)
peggy(pairs::Pair{Symbol,<:Parser}...) = NamedSequence(pairs)
function peggy(pair::Pair) 
    (p, v) = pair
    fn = if (!isa(v, Function) && isempty(methods(v)))
        fn = _ -> v
    else
        v
    end
    Map(fn, peggy(p))
end

"""
    grammar([start::Symbol], (symbol => expr)...)

Create a parser from a set of productions, which are named, mutually recursive parsers.  

Parsers that are members of a grammar can reference are member parser by their symbol.

If `start` is omitted, the symbol of the first production is used.
"""
function grammar(start::Symbol, rules::Pair{Symbol}...) 
    Grammar(GramRef(start), Dict(s => peggy(x) for (s,x) in rules))
end
grammar(rules::Pair{Symbol}...) = grammar(first(rules).first, rules...)


"""
   !(p::Parser) == not(p)
"""
Base.:(!)(p::Parser) = Not(p)
"""
    not(expr)

Create a parser that fails if parser `p` succeeds. Otherwise it succeeds with value `()`
"""
not(expr) = Not(peggy(expr))

"""
     p1::Parser | p2::Parser == oneof(p1, p2)

A short-form for [`oneof`](@ref).
"""
Base.:(|)(a::Parser, b::Parser) = OneOf([a, b])

"""
    oneof(pegexpr...)

Create a parser for ordered alternatives.
"""
oneof(expr...) = OneOf(map(peggy, expr))

"""
    p::Parser * n == many(p; min=n)
    p::Parser * (a:b) == many(p; min=a, max=b)
"""
Base.:(*)(p::Parser, minimum::Int) = Many(p, minimum, missing)
Base.:(*)(p::Parser, minmax::UnitRange) = Many(p, minmax.start, minmax.stop)
"""
    many(exprs...; min=0, max=missing)

Create a parser that matches zero or more repititions of the sequence `expr...`; returns a vector of results.
"""
many(pegexpr...; min=0, max=missing) = Many(peggy(pegexpr...),min,max)

"""
    followedby(expr...)
    !!(e::Parser)

Create a parser that matches `expr` but consumes nothing.
"""
followedby(e...) = not(not(peggy(e...))) #LookAhead(parser(e))

"""
    fail(message) => Parser

A parser that always fails with the given message.

Useful for error messages.
"""
fail(s) = Fail(s)

"""
    CHAR(charclass::String)

Create a parser for a single character matchng regex character classes. 

Functionally identical to Regex("[\$charclass]") except it is known to never match an
empty string.  This is important to avoid unneccesary and expensive left-recursion
overhead.

# Examples

```jldoctet
julia> g = @grammar begin
       number = [ digit ds:(digit...)  { parse(Int, *(digit, ds...)) } ]
       digit = CHAR("[:digit:]")
       end;

julia> g("1234")
1234
```

"""
function CHAR(charclass::String) 
    try 
        RegexParser(Regex("[$charclass]"); canmatchempty=false, pretty="CHAR(\"$charclass\"")
    catch ex
        error("Invalid characer class \"$charclass\" ($( ex.msg ))")
        print(e)
    end
end

const _ANY = RegexParser(r"."; canmatchempty=false, pretty="ANY()")
"""
A PEG parser that matches any character and yields it as a string.
"""
ANY() = _ANY

const _END = Peggy.Not(_ANY)
"""
A PEG parser that matches the end of the input; yields result `()`.
"""
END() = _END


#pegparser(s::AbstractString) = peggy(s)
#pegparser(re::Regex) = peggy(re)
#pegparser(s::Symbol) = GramRef(s)
## pegparser(v::AbstractVector) = Sequence(map(pegparser, v))
#function pegparser(pair::Pair) 
#    (p, v) = pair
#    fn = if (!isa(v, Function) && isempty(methods(v)))
#        fn = _ -> v
#    else
#        v
#    end
#    Map(fn, pegparser(p))
#end
#pegparser(p::Parser) = p
#pegparser(p1, p2, ps...) = pegparser([p1, p2, ps...])
#
##Base.@deprecate parser pegparser
#parser(x...) = pegparser(x...)