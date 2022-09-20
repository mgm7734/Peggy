const RULEARROW = :(=)
const ALTDELIM = :(/)
const MAPDELIM = :(|>)
const NAMEOP = :(:)

"""
Create a PEG parser from grammar expression.

```jldoctest ; output = false
@grammar begin
    grammar_expression = peg_expression
    peg_expression = [
        literal / regex_character_class
    ]
    regex_character_class = anych("[:alpha:]_") 
    literal = "an string"
end;

# output

grammar(:grammar_expression,
:peg_expression => oneof(:literal, :regex_character_class),
:grammar_expression => :peg_expression,
:literal => "an string",
:regex_character_class => anych("[:alpha:]_"),
```

"""
macro grammar(block)
    make_grammar(block)
end

macro peg(expr)
    make_peg(expr)
end

function make_grammar(e::Expr)
    @assert Meta.isexpr(e, :block) "Expected a block, got $e"
    rules = map(make_rule, filter(x -> x isa Expr, e.args))
    :(grammar($(rules...)))
end
function make_rule(e)
    if Meta.isexpr(e, RULEARROW)
        (sym, expr) = e.args
        @assert Meta.isidentifier(sym)
        alts = make_peg(expr)
        :($(Expr(:quote, sym)) => $alts)

    elseif Meta.isexpr(e, :call, 3) && e.args[1] == RULEARROW
        (sym, expr) = e.args[2:end]
        @assert Meta.isidentifier(sym)
        alts = make_peg(expr)
        :($(Expr(:quote, sym)) => $alts)
    else
        e
    end
end

make_peg(e::String) = :(Peggy.Literal($e))
make_peg(e::Regex) = :(Peggy.GeneralRegexParser($e))
make_peg(sym::Symbol) = :(Peggy.GramRef($(Expr(:quote, sym))))

function make_peg(e::Expr)
    if e.head in [:vect, :hcat, :row]
        make_seq(e)
    elseif e.head == :vcat
        make_alt(e.args)
        # precedence is wrong:  name:expr... == (name:expr)...
    elseif e.head == :(...)
        peg = make_peg(e.args[1])
        :(Peggy.many($peg))
    elseif Meta.isexpr(e, :call)
        (op, args...) = e.args
        if op == ALTDELIM
            make_alt(args)
        elseif op == MAPDELIM
            peg = make_peg(args[1])
            fn = args[2]
            :(Peggy.Map($fn, $peg))
        elseif op == :(!)
            peg = make_peg(args[1])
            :(Peggy.not($peg))
        #elseif op == :(&)
        #    peg = make_peg(args[1])
        #    ahead = make_peg(args[2])
        #    :(Peggy.LookAhead($peg))
        else
            e
        end
    else
        :(pegparser($e))
    end
end

function make_seq(e::Expr)
    args = e.args
    if length(args) > 1 && Meta.isexpr(last(args), :braces)
        action = last(args).args |> first
        args = args[1:end-1]
    else
        action = nothing
    end

    namedpegs = map(args) do expr
        name = nothing
        if expr isa Symbol
            name = expr
        elseif Meta.isexpr(expr, :call) && expr.args[1] == NAMEOP
            name = expr.args[2]
            if name == :_
                name = nothing
            end
            expr = expr.args[3]
        end
        make_peg(expr), name
    end
    names = tuple((n for (_, n) in namedpegs if n !== nothing)...)
    # @info "namedpegs" namedpegs n=[n for (_, n) in namedpegs if n !== nothing] names

    if length(namedpegs) == 1 && action === nothing
        return namedpegs[1][1]
    end
    if action !== nothing
        callable = :(($(names...),) -> $action)
    elseif length(names) == 1
        callable = identity
    else
        callable = :(NamedTuple{$names} ∘ tuple)
    end
    namedparsers = map(namedpegs) do (p, n)
        :(($p, $(Expr(:quote, n))))
    end
    :(Peggy.MappedSequence($callable, [$(namedparsers...)]))
end

function make_alt(args)
    pegs = map(make_peg, args)
    if length(pegs) == 1
        pegs[1]
    else
        :(Peggy.OneOf([$(pegs...)]))
    end
end

e = :(
    begin
        start = [expr not(anych())] |> first
        expr = [
            [expr "+" term] |> r -> r[1] + r[3]
            [expr "-" term] |> r -> r[1] - r[3]
            term
        ]
        term = [
            [term "*" prim] |> r -> r[1] * r[3]
            [term "/" prim] |> r -> r[1] / r[3]
            prim
        ]
        prim = [
            number
            ["(" expr ")"] |> r -> r[2]
        ]
        number = [anych("[:digit:]") many(anych("[:digit:]"))] |> r -> parse(Int, *(r[1], (r[2])...))
    end
)