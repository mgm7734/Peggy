export Parser, RegexParser

"""
    (parser::Parser)(input)

A `Peggy.Parser` is function that takes a string as input and returns its parsed value.
"""
abstract type Parser end
    
struct RegexParser <: Parser
    re::Regex
    canmatchempty::Bool
    pretty::AbstractString
    RegexParser(value_re::Regex; 
            whitespace::Regex = r"",
            canmatchempty = true, 
            pretty=string(value_re)) =
        new(Regex("^$(whitespace.pattern)(?<value>$(value_re.pattern))$(whitespace.pattern)"), canmatchempty, pretty)
end
function valueAndConsume(p::RegexParser, s::AbstractString)
    m = match(p.re, s)
    m === nothing && return nothing
    (value=m["value"], consume=m.match.ncodeunits)
end

struct Not{T<:Parser} <: Parser
    expr::T
end

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

struct OneOf <: Parser
    exprs
end

struct Many <: Parser
    expr::Parser
    min
    max
end
Many(e) = Many(e, 0, missing)

struct Fail <: Parser
    message
end

struct LookAhead <: Parser
    expr
end

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
function canmatchempty(p::Parser)
    @warn("maybempty not defined for $(typeof(p))")
    true
end
