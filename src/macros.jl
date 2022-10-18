#module Macro

#using Peggy
using MacroTools

current_line = nothing

report(message) = error("$message\nin expression starting at $(current_line.file):$(current_line.line)")

"""
Create a [`Peggy.Parser`](@ref) from a [`Peggy expression`](#Peggy-expressions)
"""
macro peg(expr)
    global current_line
    top = (current_line === nothing)
    if top
        current_line = LineNumberNode(0, "nowhere")
        try 
            toppeg(expr)
        finally
            current_line = nothing
        end
    else
        peg(expr)
    end
end

toppeg(expr) =
    if Meta.isexpr(expr, :block)
        rules = [r for r in map(rule, unblock(expr.args)) if r !== nothing]
        debug && @info "top" expr rules
        :(grammar($(rules...)))
    elseif nothing !== rule(expr)
        debug && @info "top2" expr
        toppeg(:(begin $expr end))
    else
        #@info "top" expr
        peg(expr)
    end

rule(expr::Expr) = begin
    if @capture(expr, name_Symbol = defn_)
        Meta.isidentifier(name) || report("$name must be an identifier in $expr")
        parser = peg(defn)
        debug && @info "rule" name defn parser
        :($(Expr(:quote, name)) => $parser)
    else
        nothing
    end
end
rule(lnn::LineNumberNode) = begin
    current_line = lnn
    nothing
end
rule(e) = nothing

peg(name::Symbol) = :(Peggy.GramRef($(Expr(:quote, name))))
peg(s::String) = :(peggy($s))

function peg(expr::Expr)
    debug && @info "peg" expr
    if @capture(expr, { row_ ; rows__ })
        pegcurly(row, rows)
    elseif @capture(expr, { row_ })
        pegrow(row)
    elseif @capture(expr, e_ * min_)
        max = missing
        if min == :_
            min = 0
        elseif @capture(min, (a_:b_))
            min = a
            max = b
        end
        :(many($(peg(e)), min=$min, max=$max))
    elseif @capture(expr, e_ + n_) && n === :_
        :(many($(peg(e)), min=1, max=missing))
    elseif @capture(expr, CHAR[s_String])
        :(Peggy.RegexParser(Regex("[" * $s * "]"); canmatchempty=false))
    elseif @capture(expr, op_Symbol(e__)) && op in [:(!), :(|)]
        parsers = map(peg, e)
        Expr(:call, op, parsers...)
    else
        expr
    end
end

function pegcurly(row, rows)
    parser = pegrow(row)
    debug && @info "pegcurly" row rows parser
    debug && dump(rows)
    if isempty(rows)
        parser
    else
        alts = [parser, map(pegrow, rows)...]
        :(Peggy.OneOf([$(alts...)]))
    end
end

function pegrow(row)
    debug && @info "pegrow" row Meta.show_sexpr(row)
    if isexpr(row, :vect)
        # edge case: { [ expr ]}
        (_, p) = pegseqitem(row)
        return p
    elseif !isexpr(row, :row)
        return peg(row)
    end
    args = row.args
    length(args) == 0 && report("Empty sequence is not allowd")
    length(args) == 1 && return peg(first(args))
    (fn, seqitems) = pegfnseq(args)
    parser = :(NamedSequence([$(seqitems...)]))
    if fn === nothing
        parser
    else
        :(Peggy.Map($fn, $parser))
    end
end

function pegfnseq(args)
    fn = nothing
    if length(args) > 2 && args[end-1] == :(:>)
        fn = args[end]
        args = args[1:end-2]
    end
    namedpegs = map(pegseqitem, args)
    if fn !== nothing && @capture(fn, { action_ })
        if !any(hasvar, namedpegs)
            namedpegs = [ (Symbol("x$i"), p) for (i, (_n, p)) in enumerate(namedpegs) ]
        end
        params = first.(filter(hasvar, namedpegs))
        fn = :( ($(params...),) -> $action )
        if length(params) != 1
            fn = :( Base.splat($fn) )
        end
    end
    items = [:(tuple($(Expr(:quote, n)), $p)) for (n,p) in namedpegs]
    (fn, items)
end
hasvar(t) = !startswith(t |> first |> string, '_')

function pegseqitem(item)
    debug && @info "seqitem" item
    if @capture(item, name_Symbol = e_)  
        (_, p) = pegseqitem(e)
        (name, p)
    elseif item isa Symbol
        (item, peg(item))
    elseif @capture(item, [ row_ ; rows__])
        p = pegcurly(row, rows)
        (:_, :(many($p, min=0, max=1)))
    elseif isexpr(item, :hcat)
        p = pegrow(Expr(:row, item.args...))
        (:_, :(Many($p, 0, 1)))
    elseif @capture(item, [ row__ ])
        p = pegrow(Expr(:row, row...))
        (:_, :(Many($p, 0, 1)))
    else
        (:_, peg(item))
    end
end
#end # module
#