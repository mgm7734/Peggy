const RULEARROW = :(=)
const ALTDELIM = :(/)
const MAPDELIM = :(|>)
const NAMEOP = :(:)

"""
    @grammar begin grammar_rules
    @grammar peg_expr peg_expr...

Create a PEG parser.

```jldoctest ; output = false
@grammar begin
    grammar_rule = rule_name "=" expression

    expression = [
        matrix_alt_expr
        scalar_expression
    ]
    matrix_alt_expr = [
        "[" sequence_item... ((";" / "\n") sequence_item...)... "]"
    ]
    sequence = [
        "[" sequence_item... "{" action "}" "]"
        "[" sequence_item... "]"
    ]
    sequence_item = [

    ]

    alt_expr = [
        repeat_expr ("/" repeat_expr)...
    ]
    seq_expr 
    [
        literal / regex_character_class
    ]
    repeat_expr = [ 
        primary_expr seperator_expr bounds_expr
        primary_expr bounds_expr
        primary_expr
    ]
    seperator_expr = [ ":" primary_expr ]
    bounds_expr = [ 
        ":" min:number ":" max:number
        ":" min:number "..."
        "..."
    ]
    number = anych("0-9"):1...

    regex_character_class = anych("[:alpha:]_") 
    literal = "an string"

    stmt_sep = (";" / "\n"):1...
    row_sep = ";" / "\n":1...
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

macro peg(expr...)
    make_peg(:([$(expr...)]))
end

function make_grammar(e::Expr)
    @assert Meta.isexpr(e, :block) "Expected a block, got $e"
    rules = map(make_rule, filter(x -> x isa Expr, e.args))
    :(grammar($(rules...)))
end

function make_rule(e)
    if Meta.isexpr(e, :(=))
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

function make_peg(e)
    if Meta.isexpr(e, :block)
        rules = map(make_rule, filter(x -> x isa Expr, e.args))
        :(grammar($(rules...)))
    elseif Meta.isexpr(e, [:vect, :hcat, :row])
        make_seq(e)
    elseif Meta.isexpr(e, :vcat)
        make_alt(e.args)
    else
        make_repeat(e)
    end
end

function make_alt(args)
    pegs = iteratetree(args) do e
        if iscall(e, :(/)) #Meta.isexpr(e, :call) && e.args[1] == ALTDELIM
            (nothing, e.args[2:end])
        else
            make_seq(e), nothing
        end
    end |> collect
    if length(pegs) == 1
        pegs[1]
    else
        :(Peggy.OneOf([$(pegs...)]))
    end
end

make_seq(e) = make_repeat(e)

function make_seq(e::Expr)
    args = e.args
    if length(args) > 1 && Meta.isexpr(last(args), :braces)
        action = last(args).args |> first
        args = args[1:end-1]
    else
        action = nothing
    end

    namedpegs = map(make_seqitem, args)
    names = tuple((n for (_, n) in namedpegs if n !== nothing)...)
    # @info "namedpegs" namedpegs n=[n for (_, n) in namedpegs if n !== nothing] names

    if length(namedpegs) == 1 && action === nothing
        return namedpegs[1][1]
    end
    if action !== nothing
        callable = :(($(names...),) -> $action)
    elseif length(names) == 1
        callable = identity
    elseif length(names) == 0
        callable = :(() -> ())
    else
        callable = :(NamedTuple{$names} ∘ tuple)
    end
    namedparsers = map(namedpegs) do (p, n)
        :(($p, $(Expr(:quote, n))))
    end
    :(Peggy.MappedSequence($callable, [$(namedparsers...)]))
end

make_seqitem(s::Symbol) = ( make_primary(s), s )

function make_seqitem(expr)
    @info "seqitem" expr
    name = nothing
    #if expr isa Symbol
    #    name = expr
    #    return make_primary(expr), expr
    #end
    #if Meta.isexpr(expr, :call) && expr.args[1] == :(:) && expr.args[2] isa Symbol
    if Meta.isexpr(expr, :(=))
        name = expr.args[1]
        if name === :_
            name = nothing
        end
        expr = expr.args[2]
    end
    make_repeat(expr), name
end

make_repeat(e) = make_primary(e)
function make_repeat(expr::Expr)
    @info "make_repeat" expr
    e = expr
    min = 0
    max = missing
    unbounded = false
    if expr.head == :(...)
        unbounded = true
        e = expr.args[1]
    end 
    if Meta.isexpr(e, :call) && e.args[1] == :(:)
        (e, min, max) = [e.args[2:end]..., missing, missing]
        ismissing(max) || !unbounded || error("Cannot specify both max repitions $max and '...': $expr")
    end

    peg = make_primary(e)
    @info "mk repeat" e min max peg

    if min == 0 && ismissing(max) && !unbounded
        peg
    else
        :(Many($peg, $min, $max))
    end
end

make_primary(e::String) = :(Peggy.Literal($e))
make_primary(e::Regex) = :(Peggy.GeneralRegexParser($e))
make_primary(sym::Symbol) = :(Peggy.GramRef($(Expr(:quote, sym))))

function make_primary(expr::Expr)
    # if expr isa Symbol
    #     return :(GramRef($expr))
    # end
    if !Meta.isexpr(expr, :call)
        error("huh? $expr")
        #return make_primary(expr)
    end
    (op, args...) = expr.args
    if op == ALTDELIM
        make_alt(args)
    elseif op == MAPDELIM
        peg = make_peg(args[1])
        fn = args[2]
        :(Peggy.Map($fn, $peg))
    elseif op == :(!)
        peg = make_peg(args[1])
        :(Peggy.not($peg))
    else
        expr
    end
end

iscall(e, sym) = Meta.isexpr(e, :call) && first(e.args) == sym

iteratetree(f, args) = 
    #Iterators.flatten((iter === nothing ? [v] : iter) for a in args for (v, iter) in [@show(f(a))])
    (r  for a in args 
        for (v, itr) in [f(a)] 
        for r in (itr === nothing ? [v] : iteratetree(f, itr)))
        
    

#### auxillary functions

lit(s; skiptrailing=r"\s*") = Peggy.Literal(s, skiptrailing)