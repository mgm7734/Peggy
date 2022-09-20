struct Fn{I,O}
    fn:: Function
end
function call(tf::Fn{>:I,O}, x::I)::O where {I,O}
    tf.fn(x)
end
(tf::Fn)(x) = call(tf,x)

function chain(f::Fn{A,B}, g::Fn{C,D})::Fn{A,D} where {A,B,C>:B,D}
    Fn{A,D}(x -> call(g, call(f, x)))
end

function aggr(af::Fn{Tuple{B,B},C}, fs::Vararg{Fn{>:A,B}})::Fn{A,C} where {A,B,C}
    fop(f1,f2) = x -> af((f1(x), f2(x)))
    Fn{A,C}(x->reduce(fop, fs))
end

f1=Fn{Integer, Integer}(x::Integer -> x+one(x))

f2=Fn{Real,Real}(x -> x+10)

op = Fn{Tuple{Number, Number}, Number}(((x,y)) -> x+y)

#aggr(op, f1, f1)(2)