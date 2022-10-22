using Peggy
using Test

@testset "Peggy.jl" begin

    @testset "literal" begin
        p = peggy("abc")
        @test parse(p, "abc") == "abc"
        @test_throws ["ParseException", "1", "abc"] parse(p, "aboops")

        p = peggy("a", "b", "c")
        @test parse(p, "a bcd") == ("a", "b", "c")
        @test_throws ["ParseException", "3", "c"] parse(p, "aboops")

        p = peggy(oneof("cat", "dog"))
        @test parse(p, "catetonic") == "cat"
        @test parse(p, "dogma") == "dog"
        @test_throws ["ParseException", "cat", "dog"] parse(p, "do gma")

        p = peggy(peggy("a"; whitespace=r"X*"), "b", "c")
        @test parse(p, "abcd") == ("a", "b", "c")
        @test parse(p, "XXaX b cd") == ("a", "b", "c")
        @test_throws ["ParseException"] parse(p, "aXXc")
        @test_throws ["ParseException"] parse(p, " abc")

        @test tryparse(p, " abc") === nothing
    end

   # p = peggy("abc")
   # p = many(oneof("a", "b"))
   # @test parse(p, "") == []
   # @test parse(p, "abbabca") == ["a", "b", "b", "a", "b"]

   # p = peggy("The end.", END())

   # @test parse(p, "The end.") == ("The end.", ())
   # @test_throws ["ParseException", "9"] parse(p, "The end...")

   # p = @peg {
   #         {
   #             CHAR(raw"\d")+_    :> ds -> parse(Int, *(ds...))
   #             "nix" "nada"
   #             "nix" :> { nothing }
   #             not("backtrack") cs=CHAR("[:alpha:]")+_  :> { Symbol(*(cs...)) }
   #             "backtrack!"
   #         } "."
   # }
   # @test parse(p, "42.") == (42, ".")
   # @test parse(p, "nix.") == (nothing, ".")
   # @test parse(p, "cool.") == (:cool, ".")
   # @test parse(p, "backtrack!.") == ("backtrack!", ".")
   # @test_throws ["ParseException", "5"] parse(p, "oops!")

   # maplast(vs) = map(last, vs)
   # p = @peg begin
   #     expr = { term   ts=({ "+"  term })*_    :> { sum([term, ts...]) } }
   #     term = { factor fs=({ "*", factor })*_  :> { prod([factor, fs...]) } }
   #     factor = { number ; { "(", :expr, ")" } }
   #     number = { CHAR[raw"\d"]+_ :> ds -> parse(Int, *(ds...)) }
   # end
   # @test parse(p, "2+3*4+5") == 19

    @testset "left-recursive" begin
        p = @peg begin
            start = { as END() }
            as = { 
                as "a"  :> { as * "a" }
                "a" 
            }
        end
        @test p("aaa") == "aaa"

        toylang = @peg begin
            start = { _sp expr END() }
            _sp = CHAR(raw"\s")*_ 
            expr = { 
                var "=" expr        :> { ("=", var, expr) }
                term 
            }
            term = { 
                term op=("+" | "-") prod    :> { (op, term, prod) }
                prod 
            }
            prod = { 
                prod op={ "*" ; "|" } prim  :> { (op, prod, prim) }
                prim 
            }
            prim = { 
                "-" prim        :> { ("neg", prim) }        
                "(" exp ")" ; var ; number
            }
            number = { ds=CHAR(raw"\d")+_ _sp      :> { parse(Int, *(ds...)) }  }
            var = { c=CHAR("_[:alpha:]") cs=CHAR("_[:alnum:]")*_ _sp   :> { Symbol(*(c, cs...)) } }
        end
        @test toylang("a = b = c + 3*e - f") == ("=", :a, ("=", :b, ("-", ("+", :c, ("*", 3, :e)), :f)))
    end

    @testset "macro syntax" begin

        @testset "rule" begin
            g = @peg begin
                test = {
                    as END() 
                    "action" test :> { (test, length(test)) }
                    "function" test :> length
                    "function2" as "," as :> identity
                    "number" ds=CHAR["[:digit:]"]+_ :> {parse(Int, *(ds...))}
                }
                as = {as "a" :> { as * "a" }; "a"}
            end
            @test g(repeat("a", 3)) == repeat("a", 3)
            @test g("action aaaa") == ("aaaa", 4)
            @test g("function aa") == 2
            @test g("function2 aa, a") == ("aa", "a")
            @test_throws ["ParseException", "!"] g("aaa!")
            @test g("number 420") == 420
        end

        @testset "many|cardinality" begin
            p = @peg({v="x"*_ "."})
            @test p("xx.") == ["x", "x"]
            @test p(".") == []

            p = @peg({v="y"*(1:2) "."})
            @test_throws ParseException p(".")
            @test p("y.") == ["y"]
            @test p("yy.") == ["y", "y"]
            @test_throws ParseException p("yyy.")

            p = @peg({v="x"+_ "."})
            @test p("x.") == ["x"]
            @test p("xx.") == ["x", "x"]
            @test_throws ParseException p(".")

            @test_throws ParseException @peg({ "2+"*2 })("2+")
            @test @peg({ "2+"*2 })("2+"^2) == repeat(["2+"], 2)
            @test @peg({ "2+"*2} )("2+"^4) == repeat(["2+"], 4)

            @test (@peg { "a" [ "b" ] "c" })( "ac" ) == ("a", [], "c")
            @test (@peg { "a" [ "b" ] "c" })( "abc" ) == ("a", ["b"], "c")
            @test (@peg { "a" [ "b" ; "c" "d" ] "e" })( "ae" ) == ("a", [], "e")
            @test (@peg { "a" [ "b" ; "c" "d" ] "e" })( "abe" ) == ("a", ["b"], "e")
            @test (@peg { "a" [ "b" ; "c" "d" ] "e" })( "acde" ) == ("a", [("c", "d")], "e")
        end

        @testset "misc failures fixed" begin
            p = @peg({ "A" !({"X" ; "Y"}) })
            @test p("A z") == ("A", ())
            @test_throws ParseException p("A X")

            @test @peg( "a" )( "abc" ) == "a"
            @test @peg(  Map(identity, @peg "a") )( "abc" ) == "a"
            @test @peg( { "a" } )( "abc" ) == "a"
            @test @peg( { "a" :> identity } )( "abc" ) == "a"
            @test @peg( { a="a" :> { a } } )( "abc" ) == "a"

            @test @peg({ a="a" "←" b="b" })("a  ← b ") == ("a", "b")

            p = @peg begin 
                start = { "a" followedby("b") } 
            end
            @test p("a b") == ("a", ())
            
            @test @peg({ [ "a" ] })( "a" ) == [ "a" ]
            @test @peg({ [ "a" ] })( "" ) == [ ]

           # @test @peg( { "a" "b" } )( "abc" ) == ("a", "b")
           # @test @peg( { "a" "b" : } )( "abc" ) == ()
           # @test @peg( { a="a" :> { a } } )( "abc" ) == "a"
        end

        @testset "expressions" begin
            p = @peg begin
                tests = {
                    "a !b:" a !b;
                    #"many" a*_ e
                }
                a = "A"
                b = "B"
            end
            @test p("a !b: A C") == "A"
            @test_throws ParseException p("a !b: A B")
            #@test p("ABC") == (a="A", b="B")
        end

        @testset "precedence" begin
            p = @peg begin
                alts = {
                    "simple" v=(a|b) "."
                }
                a = "A"
                b = "B"
            end

            @test p("simple A.") == "A"
            @test p("simple B.") == "B"
            @test_throws ParseException p("C.")
        end

        # #=
        g = @peg begin
            start = { 
                "" expr END()
            }
            expr = { 
                expr "+" term   :> { expr + term }
                expr "-" term   :> { expr - term }
                term
            }
            term = {
                term "*" prim   :> { term * prim }
                term "/" prim   :> { term / prim }
                prim
            }
            prim = {
                "(" expr ")"
                number 
            }
            number = {
                ds=CHAR("[:digit:]")+_ ""    :> { parse(Int, *(ds...)) }
            }
        end
        @test g("1 + 2*3 + 30 / 3 / 2 - 4") == 8
        #2# =#
    end

    @testset "LookAhead" begin
        p = @peg {r="hello" followedby(",")}
        @test p("hello, world!") == "hello"
        @test_throws ["ParseException"] p("hello!")
    end

    @testset "sequence results" begin
        @test (@peg "a")("a") == "a"
        @test (@peg {"1" "2" "3"})("123") == ("1", "2", "3")
        @test (@peg {"1" a="2" "3"})("123") == "2"
        @test (@peg {a="1" "2" b="3"})("123") == ("1", "3")
        p = @peg begin
            tests = nonsequence | nameless_seq | one_name | many_names
            nonsequence = "nonseq"
            nameless_seq = { "no" _=name "s" }
            one_name = { "one" name }
            many_names = { "has" a="many" b=name name "s" }
            name = "name"
        end
        @test p("nonseq") == "nonseq"
        @test p("no names") == ("no", "name", "s")
        @test p("one name") == "name"
        @test p("has many name names") == ("many", "name", "name")
    end
end
