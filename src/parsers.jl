export Parser, RegexParser

"""
    (parser::Parser)(input)

A `Peggy.Parser` is function that takes a string as input and returns its parsed value.
"""
abstract type Parser end
    
function canmatchempty(p::Parser)
    @warn("maybempty not defined for $(typeof(p))")
    true
end
peggy(p::Parser) = p

peggy(s::AbstractString; skiptrailing=r"\s*") = RegexParser(Regex("\\Q$s\\E"); canmatchempty=(length(s) == 0), trailing_re=skiptrailing, pretty=s)

struct RegexParser <: Parser
    re::Regex
    canmatchempty::Bool
    pretty::AbstractString
    RegexParser(value_re::Regex; trailing_re::Regex = r"", canmatchempty = true, pretty=string(value_re)) =
        new(Regex("^($(value_re.pattern))$(trailing_re.pattern)"), canmatchempty, pretty)
end
function valueAndConsume(p::RegexParser, s::AbstractString)
    m = match(p.re, s)
    m === nothing && return nothing
    (value=m.captures[1], consume=m.match.ncodeunits)
end
peggy(r::Regex) = RegexParser(r)

struct Not{T<:Parser} <: Parser
    expr::T
end
Base.:(!)(p::Parser) = Not(p)
"""
    not(p)

Create a parser that fails if parser `p` succeeds. Otherwise it succeeds with value `()`
"""
not(p) = Not(peggy(p))

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

struct NamedSequence <: Parser
    items::Vector{@NamedTuple{name::Symbol, parser::Parser,keepvalue::Bool}}
    function NamedSequence(items)
        nameditems = [( if i isa Symbol 
                            (i, GramRef(i), !startswith(string(i), '_'))
                        elseif i isa Tuple || i isa Pair{Symbol,<:Any}
                            (n, e) = i
                            (n, peggy(e), !startswith(string(n), '_'))
                        else
                            (:_, peggy(i), false) 
                        end)
                        for i in items
        ]
        keepall = !any(k for (_n, _p, k) in nameditems)
        new([ (name=n, parser=p, keepvalue=keepall || k) 
              for (n, p, k) in nameditems ])
    end
    #function NamedSequence(items::Vector{SeqItem}) 
end
sequence(items) = NamedSequence(items)
#Sequence(items) = sequence(items)
peggy(item1, item2, items...) = NamedSequence([item1, item2, items...])
peggy(items::Tuple) = NamedSequence(collect(items))

struct OneOf <: Parser
    exprs
end
Base.:(|)(a::Parser, b::Parser) = OneOf([a, b])

"""
    oneof(pegexpr...)

Create a parser for ordered alternatives.
"""
oneof(expr...) = OneOf(map(peggy, expr))

struct Many <: Parser
    expr::Parser
    min
    max
end
Many(e) = Many(e, 0, missing)
Base.:(*)(p::Parser, minimum::Int) = Many(p, minimum, missing)
Base.:(*)(p::Parser, minmax::UnitRange) = Many(p, minmax.start, minmax.stop)
"""
    many(exprs...; min=0, max=missing)

Create a parser that matches zero or more repititions of the sequence `expr...`; returns a vector of results.
"""
many(pegexpr...; min=0, max=missing) = Many(peggy(pegexpr...),min,max)

struct Fail <: Parser
    message
end

"""
    fail(message) => Parser

A parser that always fails with the given message.

Useful for error messages.
"""
fail = Fail

struct LookAhead <: Parser
    expr
end
"""
    followedby(expr)

Create a parser that matches `expr` but consumes nothing.
"""
followedby(e) = not(not(e)) #LookAhead(parser(e))

struct Map <: Parser
    callable
    expr::Parser
end
function peggy(pair::Pair) 
    (p, v) = pair
    fn = if (!isa(v, Function) && isempty(methods(v)))
        fn = _ -> v
    else
        v
    end
    Map(fn, peggy(p))
end

struct GramRef <: Parser
    sym::Symbol
end

struct LeftRecursive <: Parser
    parser:: Parser
end

struct Grammar <: Parser
    root::GramRef
    dict::Dict{Symbol,Parser}

    function Grammar(root,dict) 
        c = Compiler(dict)
        new(root, Dict(n => compile(c, n) for n in keys(dict)))
    end
end

struct Compiler
    parser::Dict{Symbol,Parser}
    leftcalls::Dict{Symbol,Set{Symbol}}
    canmatchempty::Dict{Symbol,Bool}
    function Compiler(name2parser)
        self = new(name2parser, Dict(n=>Set() for n in keys(name2parser)), Dict())
        for (n, p) in name2parser
            addleftcalls(self, p, n)
        end
        self
    end
end
compile(c, n) = n in c.leftcalls[n] ? LeftRecursive(c.parser[n]) : c.parser[n]

addleftcalls(c, p::GramRef, name) = 
    push!(c.leftcalls[name], p.sym, c.leftcalls[p.sym]...)

addleftcalls(c, parser::NamedSequence, name) =
    for item in parser.items
        addleftcalls(c, item.parser, name)
        canmatchempty(c, item.parser) || return
    end
addleftcalls(c, parser::OneOf, name) =
    for p in parser.exprs
        addleftcalls(c, p, name)
    end
addleftcalls(c, parser::Union{Many,Map,Not,LookAhead}, name) = addleftcalls(c, parser.expr, name)
addleftcalls(c, p::RegexParser, _) = nothing

#addleftcalls(c, parser, name) = nothing

canmatchempty(c, p::GramRef) = begin
    sym = p.sym
    result = get(c.canmatchempty, sym, nothing)
    if result === nothing
        c.canmatchempty[sym] = false
        c.canmatchempty[sym] = result = canmatchempty(c, c.parser[sym])
    end
    result
end
canmatchempty(c, p::NamedSequence) = all(item -> canmatchempty(c, item.parser), p.items)
canmatchempty(c, p::OneOf) = any(parser -> canmatchempty(c, parser), p.exprs)
canmatchempty(c, p::Many) = p.min == 0 || canmatchempty(c, p.expr)
canmatchempty(c, p::Map) = canmatchempty(c, p.expr)
canmatchempty(c, p::RegexParser) = p.canmatchempty
canmatchempty(c, p::Union{LookAhead,Not}) = true
canmatchempty(c, p::Fail) = false