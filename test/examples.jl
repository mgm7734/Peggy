using Peggy

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