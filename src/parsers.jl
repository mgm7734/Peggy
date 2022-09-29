export Parser, Literal, RegexParser

abstract type Parser end

struct Literal <: Parser
    value
    skiptrailing
end
Literal(s) = Literal(s, r"\s*")

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

struct Sequence <: Parser
    exprs::Vector{Parser}
end

struct MappedSequence <: Parser
    callable
    namedparsers::Vector{Tuple{Parser,Union{Symbol,Nothing}}}
    singlevalued
    function MappedSeqence(callable, items)
        new(callable, items,
            length(parsers(items)) == 1 || 
            1 == count(n->!startswith(string(n), "_"), map(last, items))
        )
    end
end
Base.names(p::MappedSequence) = map(last, p)
parsers(p::MappedSequence) = map(first, p)

SeqItem = Tuple{Symbol, Parser}
isresult(i::SeqItem) = !startswith(string(first(i)), "_")

struct NamedSequence <: Parser
    items::Vector{@NamedTuple{name::Symbol, parser::Parser,keepvalue::Bool}}
    #function NamedSequence(items::Vector{SeqItem}) 
end
function sequence(items) 
    #NamedSequence(map((np, k)->combine(first(np), last(np), k), zip(items, keepvalues(items))))
    NamedSequence([( name=first(np), parser=last(np), keepvalue=k  )
                    for (np, k) in zip(items, keepvalues(first(i) for i in items))])
end
Base.keys(p::NamedSequence) = tuple((i.name for i in p.items if i.keepvalue)...)
parsers(p::NamedSequence) = map(last, p)
function keepvalues(names) 
    [ length(names) == 1 || !startswith(string(n), "_")
      for n in names]
end

struct OneOf <: Parser
    exprs
end

struct Many <: Parser
    expr::Parser
    min
    max
    end
Many(e) = Many(e, 0, missing)

struct Not <: Parser
    expr::Parser
end

struct Fail <: Parser
    message
end

struct LookAhead <: Parser
    expr
end
followedby(e) = LookAhead(parser(e))

struct Map <: Parser
    callable
    expr::Parser
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
    maybeempty(p::Sequence) = all(maybeempty, p.exprs)
    maybeempty(p::NamedSequence) = all(maybeempty, getfield.(p.items, :parser))
    maybeempty(p::MappedSequence) = all(maybeempty, map(first, p.namedparsers))
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
    function addlrefs(p::Sequence, name::Symbol, allowed = false)
        for p2 in p.exprs
            addlrefs(p2, name, allowed)
            maybeempty(p2) || return
        end
    end
    function addlrefs(parser::NamedSequence, name::Symbol, allowed=false)
        for item in parser.items
            addlrefs(item.parser, name, allowed)
            maybeempty(item.parser) || return
        end
    end
    function addlrefs(p::MappedSequence, name::Symbol, allowed = false)
        for (p2,_) in p.namedparsers
            addlrefs(p2, name, allowed)
            maybeempty(p2) || return
        end
    end
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

