macro grammar(block)
    make_grammar(block)
end

macro peg(expr)
    if Meta.isexpr(expr, :block)
        make_grammar(expr)
    else
        make_peg(expr)
    end
end

macro peg(expr...)
    make_peg(:([$(expr...)]))
end

current_line = LineNumberNode(0, "nowhere")
report(message) = error("$message\nin expression starting at $(current_line.file):$(current_line.line)")

function make_grammar(expr::Expr)
    Meta.isexpr(expr, :block) || report("Expected a block, got $e")
    #rules = map(make_rule, filter(x -> x isa Expr, e.args))
    rules = filter(a -> a !== nothing, map(make_rule, expr.args))
    :(grammar($(rules...)))
end

function make_rule(lnn::LineNumberNode)
    global current_line = lnn
    nothing
end

function make_rule(e)
    debug && @info "rule" e
    if Meta.isexpr(e, :(=))
        (sym, expr) = e.args
        @assert Meta.isidentifier(sym) "Invalid rule name $sym in $e"
        alts = make_peg(expr)

        :($(Expr(:quote, sym)) => $alts)

    elseif Meta.isexpr(e, :call, 3) && e.args[1] == :(=)
        (sym, expr) = e.args[2:end]
        @assert Meta.isidentifier(sym)
        alts = make_peg(expr)
        :($(Expr(:quote, sym)) => $alts)
    else
        e
    end
end

function make_peg(e)
    debug && @info "peg" e
    if Meta.isexpr(e, :block)
        rules = map(make_rule, filter(x -> x isa Expr, e.args))
        :(grammar($(rules...)))
    elseif Meta.isexpr(e, [:bracescat :braces :vcat])
        make_alt(e.args)
    elseif Meta.isexpr(e, [:vect, :hcat])
        # [ e... ] => { e... }*(0:1)
        p = make_seq(e.args)
        :(Peggy.Many($p, 0, 1))
    #elseif Meta.isexpr(e, [:row])
    #    @warn "does this happen?"
    #    (onerow=e.args,)
    #elseif Meta.isexpr(e, [:bracescat, :braces, :vect, :hcat, :row])
    #    make_seq(e)
    #    #make_rows(e.args)
    #elseif Meta.isexpr(e, [:bracescat, :vcat])
    #    make_alt(e.args)
    else
        make_repeat(e)
    end
end

function make_alt(args::Array)
    debug && @info "alt" args
    #pegs = iteratetree(args) do e
    #    if iscall(e, :(/)) 
    #        (nothing, e.args[2:end])
    #    else
    #        make_seq(e), nothing
    #    end
    #end |> collect
    pegs = map(make_seq, args)
    if length(pegs) == 1
        first(pegs)
    else
        :(Peggy.OneOf([$(pegs...)]))
    end
end

make_seq(e) = make_repeat(e)

function make_seq(expr::Expr)
    if Meta.isexpr(expr, :row)
        make_seq(expr.args)
    else
        make_peg(expr)
    end
end
function make_seq(args::AbstractArray)
    debug && @info "seq" args
    if length(args) > 1 && Meta.isexpr(last(args), :braces) && Meta.isexpr(last(args).args[1], :braces)
        # TODO: remove this. Use :>
        # Handle `expr {{ action }}` syntax
        action = last(args).args[1].args |> first
        args = args[1:end-1]
    elseif length(args) > 2 && args[end-1] === :(:>)
        # Handle `expr... :> { action }` and `expr... :> fn` syntax
        fn = args[end]
        args = args[1:end-2]
        if Meta.isexpr(fn, :braces)
            action = first(fn.args)
        else
            p = make_seq(args)
            return :(Map($fn, $p))
        end
    else
        action = nothing
    end

    items = map(make_seqitem, args)
    names = map(np->first(np), items)
    keptnames = [n for (n,k) in zip(names, keepvalues(names)) if k]
    #tups = [:( (name=Symbol($(string(np))), parser=$(last(np))) ) for np in items]
    tups = [:( (Symbol($(string(first(np)))), $(last(np))) ) for np in items]
    parser = :(Peggy.namedSequence([$(tups...)]))
    if length(keptnames) == 1 && action === nothing
        return parser
    end
    if action === nothing
        return parser
    end
    #@info "callable args" keptnames action
    callable = :( ($(keptnames...),) -> $action )
    #@info "callable" callable
    :(Map($callable, $parser))
end

make_seqitem(s::Symbol) = (name=s, parser=make_primary(s))

function make_seqitem(expr)
    debug && @info "seqitem" expr
    if Meta.isexpr(expr, :(=))
        (_, p) = make_seqitem(expr.args[2])
        (name = expr.args[1], parser=p)
    else
        p = make_repeat(expr)
        (name=:_, parser=p)
    end
end

function make_repeat(expr::Expr)
    #if Meta.isexpr(expr, :vect) && length(expr.args) == 1 && expr.args isa String
    #end
    if iscall(expr, :(*))
        length(expr.args) == 3 || report("TODO: better error for non-binary *")
        (e, bounds) = expr.args[2:end]
        parser = make_primary(e)
        (min,max) = if (bounds == :_)
            (0, missing)
        elseif bounds isa Integer
            (bounds,missing)
        elseif iscall(bounds, :(:))
            (bounds.args[2], bounds.args[3])
        end
        :(Many($parser, $min, $max))
    elseif iscall(expr, :(+)) && expr.args[3:end] == [:_]
        parser = make_primary(expr.args[2])
        :(Many($parser, 1, missing))
    else
        make_primary(expr)
    end
end

make_repeat(expr) = make_primary(expr)

make_primary(e::String) = :(Peggy.Literal($e))
make_primary(e::Regex) = :(Peggy.GeneralRegexParser($e))

function make_primary(sym::Symbol) 
    Meta.isidentifier(sym) || report("'$sym' Not valid here")
    :(Peggy.GramRef($(Expr(:quote, sym))))
end

function make_primary(expr::Expr)
    if expr.head == :(||)
        return make_alt(expr.args)
    end
    if !Meta.isexpr(expr, :call)
        # this handles blocks
        return make_peg(expr)
        # return :(begin 
        #     p = $expr 
        #     @assert p isa Parser "$expr: must return a parser"
        #     p
        # end)
    end
    (op, args...) = expr.args
    if op == :(/)
        make_alt(args)
    elseif op == :(|>)
        peg = make_repeat(args[1])
        fn = args[2]
        :(Peggy.Map($fn, $peg))
    elseif op in [:!, :followedby]
        Expr(:call, op, map(make_peg, args)...)
    else
        expr
    end
end
Base.:(!)(p::Parser) = Peggy.Not(p)

iscall(e, sym) = Meta.isexpr(e, :call) && first(e.args) == sym

iteratetree(f, args) =
#Iterators.flatten((iter === nothing ? [v] : iter) for a in args for (v, iter) in [@show(f(a))])
    (r for a in args
     for (v, itr) in [f(a)]
     for r in (itr === nothing ? [v] : iteratetree(f, itr)))

#### auxillary functions

lit(s; skiptrailing=r"\s*") = Peggy.Literal(s, skiptrailing)