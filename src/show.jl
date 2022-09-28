#function Base.show(io::IO, parser::Parser) 
#  Base.print(io, "parser(")
#    showparser(io, parser)
#    Base.print(io, ")")
#end

Base.show(io::IO, ::MIME"text/plain", p::Parser) = pretty(io, p)
pretty(io::IO, p, _) = pretty(io::IO, p)
#pretty(io::IO, p) = Base.show(io::IO, MIME("text/plain"), p)
pretty(io::IO, p::Literal) = show(io, MIME("text/plain"), p.value)
function pretty(io::IO, p::LookAhead) 
    print(io, "followedby(")
    pretty(io,  p.expr)
    print(io, ")")
end
pretty(io::IO, p::RegexParser) = print(io, p.re)
pretty(io::IO, p::GramRef) = print(io, string(p.sym))
function pretty(io::IO, p::Not)
    print(io, "!")
    pretty(io, p.expr)
end

function pretty(io::IO, p::OneOf) 
    print(io, "{ ")
    join(io, (sprint(pretty, p, true) for p in p.exprs), " ; ")
    print(io, " }")
end

function pretty(io::IO, p::Many) 
    pretty(io, p.expr)
    if !ismissing(p.max)
        print(io, "*($(p.min):$(p.max))")
    elseif p.min == 0
        print(io, "*_")
    elseif p.min == 1
        print(io, "+_")
    else
        print(io, "*$(p.min)")
    end
end

function pretty(io::IO, p::NamedSequence) 
    pretty(io, p, false)
end

function pretty(io::IO, p::NamedSequence, inrow)
    if !inrow
        print(io, "{")
    end
    join(io, (sprint(prettyseqitem, p) for p in p.items), " ")
    if !inrow
        print(io, "}")
    end
end
function prettyseqitem(io::IO, item) 
    rename = 
        if item.parser isa GramRef 
            item.name != item.parser.sym
        else
            item.name != :_
        end
    if rename
        print(io, string(item.name))
        print(io, "=")
    end
    show(io, MIME("text/plain"), item.parser)
end

function pretty(io::IO, p::Map)
    #print(io, "Map(", io, p.callable, ",")
    print(io, "Map(")
    print(io, p.callable)
    print(io, ",")
    pretty(io, p.expr)
    print(io, ")")
end

function Base.showerror(io::IO, ex::ParseException)
    print(io, "ParseException")
    st = ex.state
    printpos(io, st.input, st.maxfailindex)
    print(io, "expected: ")
    #oshowparserlist(io, "", unique(st.expected); delim=", ", last=", or ")
    #oprint(io, unique(st.expected))
    join(io, (sprint(show, MIME("text/plain"), p) for p in st.expected), " or ")
    
end

function printpos(io::IO, s::AbstractString, pos::Int)
    if isempty(s)
        print(io, " in empty string")
        return
    end
    pos = min(pos, length(s))
    thrupos = SubString(s, 1, pos)
    m = match(r"[^\n]*.$"s, thrupos);
    m === nothing && @info "printpos" thrupos pos s
    before = m.match;
    pointer = " "^(length(before)-1) * "^"
    text = match(r".*", SubString(s, m.offset)).match
    lineno = count(==('\n'), SubString(s, 1, pos)) + 1
    colno = length(pointer)
    print(io, " at line ")
    print(io, lineno)
    print(io, " column ")
    print(io, colno)
    println(io, ":")
    println(io, text)
    println(io, pointer)
end

function showparserlist(io, before, parsers, after=""; delim = ", ", last=delim)
    Base.print(io, before)
    if !isempty(parsers)
        (e1, es...) = parsers
        showparser(io, e1)
        for (i, e) in enumerate(es)
            Base.print(io, i == length(es) ? last : delim)
            showparser(io,e)
        end
    end
    Base.print(io, after)
end

showparser(io::IO, parser::Literal) = show(io, parser.value)
showparser(io::IO, parser::RegexParser) = show(io, parser.re)
function showparser(io::IO, parser::NonemptyRegex)
    if (parser.re.pattern == ".")
        print(io, "anych()")
    else
        print(io, "anych(\"")
        print(io, parser.re.pattern[2:end-1])
        print(io, "\")")
    end
end
showparser(io::IO, parser::Sequence) = showparserlist(io, "[", parser.exprs, "]")
function showparser(io::IO, parser::MappedSequence)
    # TODO
    showparserlist(io, "[", map(first, parser.namedparsers), "]")
end
showparser(io::IO, parser::OneOf) = showparserlist(io, "oneof(", parser.exprs, ")")
function showparser(io::IO, parser::Many)
    Base.print(io, "many(")
    if parser isa Sequence
        showparserlist(io, "", parser.expr.exprs , "")
    else
        showparser(io, parser.expr)
    end
    Base.print(io, ")")
end

showparser(io::IO, parser::Not) = showparserlist(io, "not(", [parser.expr], ")")
function showparser(io::IO, parser::Map) 
    showparser(io, parser.expr)
    Base.print(io, " => ")
    show(io, parser.callable)
end

showparser(io::IO, parser::GramRef) = show(io, parser.sym)
showparser(io::IO, parser::LeftRecursive) = showparser(io, parser.parser)

#=
function Base.show(io::IO, parser::Grammar) 
    print(io, "grammar(")
    showparser(io, parser.root)
    Base.println(io, ",")
    for (sym, p) in parser.dict
        show(io, sym)
        Base.print(io, " => ")
        showparser(io, p)
        Base.println(io, ",")
    end
    Base.print(")")
end
=#
