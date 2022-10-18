using Peggy

#=
"""
Adapted from [this article](https://pdos.csail.mit.edu/~baford/packrat/thesis/thesis.pdf)
"""
peg_grammar = grammar(
    :start => [:spaces, :grammar, END] => x -> x[2],

    :grammar => [:production, many(:production)] => 
                    x-> parser([x[1], x[2]...]),
    :production => [:identifier, :COLON, :rule] => 
                    x-> (Symbol(x[1]) => x[3]),
    :rule => :altrule,
    :altrule => [:seqrule, many(:SLASH, :seqrule)] =>
                    x-> oneof(x[1], map(last, x[2])...),
    :seqrule => [:unaryrule, many(:unaryrule)] =>
                    x -> parser(x[1], x[2]...),
    :unaryrule => oneof(
                    [:primrule, :QUESTION] => x -> oneof(not(x[1]), x[1]),
                    [:primrule, :STAR] => x -> Peggy.Many(x[1]),
                    [:primrule, :PLUS] => x -> Peggy.Sequence([x[1], Peggy.Many(x[1])]),
                    ["!", :spaces, :primrule] => Peggy.Not∘last,
                    :primrule),
    :primrule => oneof(
        [:identifier, not(":"), :spaces] => Peggy.GramRef∘Symbol∘first,
        :stringlit => Peggy.Literal,
        [:OPEN, :rule, :CLOSE] => x -> x[2]
    ),
    
    :identifier => [:identstart, many(:identcont)] => 
                    x -> *(x[1], x[2]...),
    :identstart => oneof(:LETTER, "_"),
    :identcont => oneof(:identstart, :DIGIT),

    :stringlit => [:QUOTE, many(not(:QUOTE), :quotedchar), :QUOTE, :spaces] => 
                    x -> if isempty(x[2])
                        ""


                    else
                        *((map(last, x[2]))...)
                    end,
    :quotedchar => oneof(
        "\\n" => "\n",
        "\\r" => "\r",
        "\\t" => "\t",
        "\\\"" => "\"",
        "\\\\" => "\\",
        [not("\\"), r"."] => last
    ),
    :spaces => many(oneof(:SPACECHAR, :linecomment)),
    :linecomment => ["#", many(not(:NEWLINE), anych()), :NEWLINE],

    :CLOSE => [")", :spaces],
    :COLON => [":", :spaces],
    :DIGIT => anych("[:digit]"),
    :LETTER => anych( "[:alpha:]" ),
    :NEWLINE => oneof("\r\n", "\r", "\n"),
    :OPEN => ["(", :spaces],
    :PLUS => ["+", :spaces],
    :QUESTION => ["?", :spaces],
    :QUOTE => "\"",
    :SLASH => ["/", :spaces],
    :SPACECHAR => anych("[:space:]"),
    :STAR => ["*", :spaces],
    )

    toylang = grammar(
        :START => [:_, :expr, END] => x -> x[2],
        :expr => oneof(
            [:var,  "=", :_, :expr] => x -> ("=", first(x), last(x)), 
            :term),
        :term => oneof(
            [:term, "+", :_, :prod ] => x -> ( "+", first(x), last(x) ),
            [:term, "-", :_, :prod ] => x -> ( "-", first(x), last(x) ),
            :prod),
        :prod => :prim,
        :prim => oneof(
            :var, 
            ["(", :_, :expr, ")", :SP] => x -> x[3]),
        :var => [:LETTER, many(oneof(:LETTER,:DIGIT,"_")), :_] => x -> Symbol(*(x[1], (x[2])...)),

        :_ => many(anych("[:space:]")),
        :DIGIT => anych("[:digit]"),
        :LETTER => anych("[:alpha:]"),
        :NEWLINE => oneof("\r\n", "\r", "\n"),
    )
=#
peggypeg = @peg begin
    parser =  { "" v=( grammar | expression ) END() }
    
    grammar = { # just Julia syntax for a block of `rule` productions
        _begin r1=rule rs={ _sep1 rule }*_  _end            :> { Peggy.Grammar(r1.first, Dict(rule, rs...)) }
        "(" r1=rule _sep2 rs={ _sep2 rule } ")"             :> { Peggy.Grammar(r1.first, Dict(rule, rs...)) }
    } 
    _begin = { "begin" [ _sep1 ] }
    _sep1 = (";" | "\n")+_
    _sep2 = { 
        ";" (";" | "\n")*_ 
    }
    rule = { rule_name "=" expession                        :> { rule_name => expression } }
    rule_name = { Identifier        :> Symbol }
    
    expression = {
        # `expr |> f1=expr |> fn` is valid if f1 returns a `Parser`.
        alt_expr ":>" fn=julia_expression                   :> { Peggy.Map(fn, alt_expr) }
        alt_expr
    }
    alt_expr =  {
        a1=rep_expr as={"|" rep_expr}*_                    :> { OneOf([a1, as...])}
        rep_expr
    }
    rep_expr= {
        primary_expr "*" c=cardnality                       :> { many(primary_expr; min=c.min, max=c.max) }
        primary_expr "+" "_"                                :> { many(primary_expr; min=1, max=missing) }
        "[" primary_expr "]"                                :> { many(primary_expr; min=0, max=1) }
        "!" primary_expr                                    :> Peggy.Not
        primary_expr
    }
    cardnality = {
        "_"                                             :> { (min=0, max=nothing) } 
        "(" min=Number ":" max=Number ")"
        Number                                          :> { ( min=Number, max=nothing ) }
    }
    primary_expr = {
        String                                          :> peggy
        Regex                                           :> peggy
        "CHAR(" s=String ")"                                :> { CHAR(s) } 
        "ANY()"                                            :> { ANY() }
        "followedby(" e=expression ")"                  :> { LookAhead(e) }
        "{" !"{" sequence_body "}"
        "(" expression ")"
    }
    
    sequence_body = mapped_sequence | sequence 
    mapped_sequence = { 
        s=sequence ":> {" Action "}"                 :> { Peggy.Map(make_action(names(s), Action), s) }
    }
    sequence = {
        sequence_item*_                             :> Peggy.NamedSequence
    }
    sequence_item = { 
        name=rule_name "=" parser=expression 
        expression                                  :> { (name=:_, parser=expression) }
    }
    
    # Julia parsed items w/ approximate implementations

    Number = { ds=CHAR("0-9")+_                         :> { parse(Int, ds) } }

    Identifier = {
        c1=CHAR("[:alpha:]_") cs=CHAR("[:alnum:]_!")*_      :> { Symbol(*(c1, cs...)) }
    }
    Action = {
        { cs=CHAR(".")*_                                     :> { Meta.parse(*(cs)) } }
    }
    String = {
        "\"" cs=qchar*_ "\""                        :> { *("", cs...) }
    }
    qchar = { 
        "\\" c={"\"" ; "\\"}                         # :> { "\\$c" }
        !({"\"" ; "\\"}) c=ANY()
    }
    Regex = { "r\"" s=String "\""                    :> { Regex(s)} }
end;

# a^n b^n c^n
abc = @peg begin
    s = { !!({ ab "c" }) "a"+_ bc END()}
    ab = { "a" [ ab ] "b" }
    bc = { "b" [ bc ] "c" }
end