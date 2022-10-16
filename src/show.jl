#function Base.show(io::IO, parser::Parser) 
#  Base.print(io, "parser(")
#    showparser(io, parser)
#    Base.print(io, ")")
#end

function Base.show(io::IO, ::MIME"text/plain", p::Parser) 
    print(io, "@peg(")
    pretty(io, p)
    print(io, ")")
end

pretty(io::IO, p, _) = pretty(io::IO, p)
function pretty(io::IO, pre::String, p, post::String)
    print(io, pre)
    pretty(io, p)
    print(io, post)
end
#pretty(io::IO, p) = Base.show(io::IO, MIME("text/plain"), p)
#pretty(io::IO, p::Literal) = show(io, MIME("text/plain"), p.value)
pretty(io::IO, p::Fail) = print(io, p.message)
function pretty(io::IO, p::LookAhead) 
    print(io, "followedby(")
    pretty(io,  p.expr)
    print(io, ")")
end
pretty(io::IO, p::RegexParser) = showparser(io, p)
pretty(io::IO, p::GramRef) = print(io, string(p.sym))

 pretty(io::IO, p::Not{<:Not}) = pretty(io::IO, "followedby(", p.expr.expr, ")")
   
function pretty(io::IO, p::Not)
    if p.expr == ANY()
        print(io, "END()")
    else
        print(io, "!")
        pretty(io, p.expr)
    end
end

function pretty(io::IO, p::OneOf, inrow = false) 
    inrow || print(io, "{ ")
    join(io, (sprint(pretty, p, true) for p in p.exprs), " ; ")
    inrow || print(io, " }")
end

function pretty(io::IO, p::Many) 
    if p.min == 0 && !ismissing(p.max) && p.max == 1
        print(io, "[")
        pretty(io, p.expr, true)
        print(io, "]")
        return
    end
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

function pretty(io::IO, p::NamedSequence, inrow; map::Any=nothing)
    if !inrow
        print(io, "{")
    end
    join(io, (sprint(prettyseqitem, p) for p in p.items), " ")
    if map !== nothing
        print(io, " :> ")
        show(io, MIME("text/plain"), map)
    end
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
    pretty(io, item.parser)
end

function pretty(io::IO, p::Map)
    if p.expr isa NamedSequence
        pretty(io, p.expr, false; map=p.callable)
        return
    end
    print(io, "Map(")
    print(io, p.callable)
    print(io, ", ")
    #pretty(io, p.expr)
    show(io, MIME("text/plain"), p.expr)
    print(io, ")")
end

pretty(io::IO, parser::LeftRecursive) = pretty(io, parser.parser)

function pretty(io::IO, parser::Grammar)
    print(io, "begin\n  ")
    join(io, (sprint(prettyrule, sym, p) for (sym,p) in parser.dict), "\n  ")
    print(io, "\nend")
end
function prettyrule(io, sym, p)
    print(io, sym, "=")
    pretty(io, p)
end

function Base.showerror(io::IO, ex::ParseException)
    print(io, "ParseException")
    st = ex.state
    printpos(io, st.input, st.maxfailindex)
    print(io, "expected: ")
    join(io, (sprint(pretty, p) for p in st.expected), " or ")
    
end

function printpos(io::IO, s::AbstractString, pos::Int; file="(no file)")
    if isempty(s)
        println(io, " in empty string")
        return
    end
    if pos >= length(s)
        s = s * " "
    end
    m = match(r"[^\n]*.$"s, SubString(s, 1, pos)) 

    before = m.match;
    pointer = " "^(length(before)-1) * "^"
    text = match(r".*", SubString(s, m.offset)).match
    lineno = count(==('\n'), SubString(s, 1, pos)) + 1
    colno = length(pointer)
    print(io, " @ ")
    print(io, file)
    print(io, ":")
    print(io, lineno)
    print(io, ":")
    println(io, colno)
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

showparser(io::IO, parser::RegexParser) = print(io, parser.pretty)

showparser(io::IO, parser::OneOf) = showparserlist(io, "oneof(", parser.exprs, ")")
function showparser(io::IO, parser::Many)
    Base.print(io, "many(")
    #if false #parser isa Sequence
    #    showparserlist(io, "", parser.expr.exprs , "")
    #else
    showparser(io, parser.expr)
    #end
    Base.print(io, ")")
end

#showparser(io::IO, parser::Not) = showparserlist(io, "not(", [parser.expr], ")")
showparser(io::IO, parser::Not) = showparserlist(io, "not(", [parser.expr], ")")
showparser(io::IO, parser::Not{<:Not}) = showparserlist(io, "followedby(", [parser.expr.expr], ")")

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
