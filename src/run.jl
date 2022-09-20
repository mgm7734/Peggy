MaybeValue = Union{Some,Nothing}

mutable struct SavedResult
    endindex::Int
    value::MaybeValue
end

struct ResultCache
    d::Dict{Symbol, Dict{Int, SavedResult}}
end
ResultCache() = ResultCache(Dict())

cacheForGramRef(rc::ResultCache, ref::GramRef) =
    get!(rc.d, ref.sym, Dict{Int, SavedResult}())

mutable struct State
    const input::AbstractString
    productions::Dict{Symbol,Any}
    index::Int
    maxfailindex::Int
    expected::Vector{Parser}
    value::MaybeValue
    resultcache::ResultCache
end
State(i, productions) = State(i, Dict(), 1, 0, [], nothing, ResultCache())
State(i) = State(i, Dict())
mark(st::State) = st.index
function reset(st::State, pos)
    st.index = pos
end

struct ParseException <: Exception
    state::State
end

value(st::State) = something(st.value)
remainingtext(st::State) = SubString(st.input, st.index)
isfail(st::State) = (st.value === nothing)

function succeed!(st::State, result, consumed=0)
    st.value = Some(result)
    st.index += consumed
    st
end

function fail!(st::State, expected::Parser...)
    st.value = nothing
    if !PRETTY_ERROR
        st.maxfailindex = max(st.index, st.maxfailindex)
    elseif isempty(st.expected) || st.index > st.maxfailindex
        st.maxfailindex = st.index
        st.expected = collect(expected)
    elseif st.index == st.maxfailindex
        push!(st.expected, expected...)
    end
    st
end

"""
    runpeg(e::Parser, s::AbstractString) => result_value

Parse the input with the parser.

Returns the resulting value or throws a `ParseException`.
"""
function runpeg(parser::Parser, input::AbstractString)
    st = State(input)
    if isfail(calcnextstate!(st, parser)) 
        throw(ParseException(st))
    end
    value(st)
end
runpeg(p, i) = runpeg(parser(p), i)
"""
    (parser::Parser)(input)

Parsers are callable.
"""
(parser::Parser)(input) = runpeg(parser, input)

nextstate!(st::State, parser) = calcnextstate!(st, parser)

function calcnextstate!(st::State, p::Literal)
    if startswith(remainingtext(st), p.value)
        succeed!(st, p.value, length(p.value))
    else
        fail!(st, p)
    end
end

function calcnextstate!(st::State, parser::RegexParser)
    s = remainingtext(st)
    if !startswith(s, parser.re)
        fail!(st, parser)
    else
        m = match(parser.re, s)
        succeed!(st, m.match, length(m.match))
    end
end

function calcnextstate!(st::State, p::Sequence) 
    values = [] 
    for p′ in p.exprs
         nextstate!(st, p′)
        if isfail(st)
            return st
        end
        push!(values, value(st))
    end
    # debug && @info "chain" values 
    succeed!(st, tuple(values...))
end

function calcnextstate!(st::State, p::MappedSequence) 
    values = [] 
    for (parser, name) in p.namedparsers
        if isfail(nextstate!(st, parser))
            return st
        end
        if (name !== nothing)
            push!(values, value(st))
        end
    end
    v = p.callable(values...)
    succeed!(st, v)
end

function calcnextstate!(st::State, parser::OneOf)
    ix = st.index
    for p in parser.exprs
        nextstate!(st, p)
        if !isfail(st)
            return st
        end
        st.index = ix
    end
    fail!(st, parser)
end

function calcnextstate!(st::State, parser::Many)
    values = []
    while true
        nextstate!(st, parser.expr)
        if isfail(st)
            return succeed!(st, [values...])
        end
        push!(values, value(st))
    end
end

function calcnextstate!(st::State, parser::Not)
    ix = st.index
    nextstate!(st, parser.expr)
    if isfail(st)
        succeed!(st, ())
    else
        st.index = ix
        fail!(st, parser)
    end
end

function  calcnextstate!(st::State, parser::LookAhead)
    startpos = mark(st)
    calcnextstate!(st::State, parser.expr)
    reset(st, startpos)
    st
end

function calcnextstate!(st::State, parser::Map)
    nextstate!(st, parser.expr)
    if isfail(st)    
        st
    else
        val = parser.callable(value(st))
        debug && @info "map" st.value val
        succeed!(st, val)
    end
end

function calcnextstate!(st::State, parser::Grammar)
    st.productions = parser.dict
    nextstate!(st, parser.root)
end
function calcnextstate!(st::State, ref::GramRef)
    expr = st.productions[ref.sym]
    # left recursion: https://medium.com/@gvanrossum_83706/left-recursive-peg-grammars-65dab3c580e1
    startindex = st.index
    refcache = cacheForGramRef(st.resultcache, ref)
    savedresult = get(refcache, startindex, nothing) 
    #debug && @info "start: $(ref.sym) at $(startindex)"
    if savedresult === nothing
        if expr isa LeftRecursive
            expr = expr.parser
            # prime cache with failure so an alternate rule succeeds
            refcache[startindex] = savedresult = SavedResult(startindex, nothing)
            while true
                nextstate!(st, expr)

                isfail(st) && break
                st.index <= savedresult.endindex && savedresult.value !== nothing && break

                savedresult.value =  st.value
                savedresult.endindex = st.index
                debug && @info "found :$(ref.sym) $startindex:$(savedresult.endindex) => $(savedresult.value)"

                st.index = startindex
            end
            debug && @info "YIELD :$(ref.sym) $startindex:$(savedresult.endindex) => $(savedresult.value)"
        else
            savedresult = get!(cacheForGramRef(st.resultcache, ref), startindex) do
                nextstate!(st, st.productions[ref.sym])
                debug && !isfail(st) && @info ref.sym startindex st.index value(st)
                SavedResult(st.index, st.value)
            end
        end
    end
    st.index = savedresult.endindex
    st.value = savedresult.value
    st
end
