export Parser, Literal, RegexParser

"""
    (parser::Parser)(input)

A `Peggy.Parser` is function that takes a string as input and returns its parsed value.
"""
abstract type Parser end

peggy(p::Parser) = p

struct Literal <: Parser
    value
    skiptrailing
end
Literal(s; skiptrailing=r"\s*") = Literal(s, skiptrailing)
peggy(s::String; skiptrailing=r"\s*") = Literal(s, skiptrailing)

abstract type RegexParser <: Parser end

struct GeneralRegexParser <: RegexParser
    re::Regex
end

"""
Succeeds with a non-empty value.
"""
struct NonemptyRegex <: RegexParser
    re::Regex
end
peggy(r::Regex) = NonemptyRegex(r)

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
        NonemptyRegex(Regex("[$charclass]"))
    catch ex
        error("Invalid characer class \"$charclass\" ($( ex.msg ))")
        print(e)
    end
end

"""
A PEG parser that matches any character and yields it as a string.
"""
ANY() = NonemptyRegex(r".")

"""
A PEG parser that matches the end of the input; yields result `()`.
"""
END() = !ANY()

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
#    #NamedSequence(map((np, k)->combine(first(np), last(np), k), zip(items, keepvalues(items))))
#    NamedSequence([( name=first(np), parser=last(np), keepvalue=k  )
#                    for (np, k) in zip(items, keepvalues(first(i) for i in items))])
#end
#Base.keys(p::NamedSequence) = tuple((i.name for i in p.items if i.keepvalue)...)
#parsers(p::NamedSequence) = map(last, p)
#function keepvalues(names) 
#    [ length(names) == 1 || !startswith(string(n), "_")
#      for n in names]
#end

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


struct Not <: Parser
    expr::Parser
end
Base.:(!)(p::Parser) = Not(p)
"""
    not(p)

Create a parser that fails if parser `p` succeeds. Otherwise it succeeds with value `()`
"""
not(p) = Not(peggy(p))

struct Fail <: Parser
    message
end
"""
"""
fail = Fail

struct LookAhead <: Parser
    expr
end
followedby(e) = LookAhead(parser(e))

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
    # jGrammar(root,dict) = new(root, dict, left_resursive_names(dict))
    function Grammar(root,dict) 
        lrnames = left_resursive_names(dict)
        dict = Dict((name => (name in lrnames) ? LeftRecursive(p) : p)
                    for (name, p) in dict)
        new(root, dict)
    end
end

function left_resursive_names(productions)
    emptysyms = Dict{Symbol,Bool}()
    maybeempty(p::Literal) = p == ""
    maybeempty(p::GeneralRegexParser) = true
    maybeempty(p::NonemptyRegex) = false
    # maybeempty(p::Sequence) = all(maybeempty, p.exprs)
    maybeempty(p::NamedSequence) = all(maybeempty, getfield.(p.items, :parser))
    #maybeempty(p::MappedSequence) = all(maybeempty, map(first, p.namedparsers))
    maybeempty(p::OneOf) = any(maybeempty, p.exprs)
    maybeempty(p::Many) = true
    maybeempty(p::Not) = true
    maybeempty(p::Map) = maybeempty(p.expr)
    function maybeempty(p::GramRef)  
        r = get(emptysyms, p.sym, nothing)
        if r === nothing
            # in case recursive
            emptysyms[p.sym] = false
            emptysyms[p.sym] = r = maybeempty(productions[p.sym])
        end
        r
    end

    #@info "empty syms" Dict(k=>maybeempty(GramRef(k)) for k in keys(productions))
        
    leftrefs = Dict(k=>Set() for k in keys(productions))
    addlrefs(::Literal, name, allowed) = ()
    addlrefs(::RegexParser, name::Symbol, allowed) = ()
    # function addlrefs(p::Sequence, name::Symbol, allowed = false)
    #     for p2 in p.exprs
    #         addlrefs(p2, name, allowed)
    #         maybeempty(p2) || return
    #     end
    # end
    function addlrefs(parser::NamedSequence, name::Symbol, allowed=false)
        for item in parser.items
            addlrefs(item.parser, name, allowed)
            maybeempty(item.parser) || return
        end
    end
    #function addlrefs(p::MappedSequence, name::Symbol, allowed = false)
    #    for (p2,_) in p.namedparsers
    #        addlrefs(p2, name, allowed)
    #        maybeempty(p2) || return
    #    end
    #end
    function addlrefs(p::OneOf, name::Symbol, allowed = false)
        for p2 in p.exprs
            addlrefs(p2, name, allowed)
            allowed |= !maybeempty(p2)
        end
    end
    function addlrefs(p::Many, name::Symbol, allowed = false) 
        addlrefs(p.expr, name, allowed)
    end
    function addlrefs(p::Not, name::Symbol, allowed = false) 
        addlrefs(p.expr, name, allowed)
    end
    function addlrefs(p::Map, name::Symbol, allowed = false) 
        addlrefs(p.expr, name, allowed)
    end
    function addlrefs(p::GramRef, name::Symbol, allowed = false) 
        result = leftrefs[name]
        push!(result, p.sym, leftrefs[p.sym]...)
    #!allowed && name in result && @warn("'$name' has invalid left recursion")
    end

    for n in keys(productions)
        addlrefs(productions[n], n, false)
    end

    Set(name for (name,refs) in leftrefs if name in refs)
end

