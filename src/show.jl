function Base.show(io::IO, parser::Parser) 
  Base.print(io, "parser(")
    showparser(io, parser)
    Base.print(io, ")")
end

function Base.showerror(io::IO, ex::ParseException)
    print(io, "ParseException at ")
    st = ex.state
    printpos(io, st.input, st.maxfailindex)
    print(io, "expected: ")
    #oshowparserlist(io, "", unique(st.expected); delim=", ", last=", or ")
    print(io, unique(st.expected))
end

function printpos(io::IO, s::AbstractString, pos::Int)
    println(io, "at index $pos in: $s")
    return
    # TODO: use Regex
    bol = something(findlast('\n', SubString(s, 1, pos)), 0) + 1
    eol = something(findnext(==('\n'), s, pos), length(s))
    if pos != eol
        eol -= 1
    end
    lineno = count(==('\n'), SubString(s, 1, pos)) + 1
    #@info "printpos" pos bol eol lineno length(s) s
    print(io, "line ")
    print(io, lineno)
    print(io, " column ")
    print(io, pos - bol + 1)
    println(io, ":")
    println(io, SubString(s, bol, eol))
    print(io, " "^(pos - bol))
    println(io, "^")
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
