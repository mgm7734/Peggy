using Peggy
using Test

@testset "Peggy.jl" begin
    p = parser("abc")
    #=
    @test runpeg(p, "abcd") == "abc"
    @test_throws ["ParseException","1", "abc"] runpeg(p, "aboops")

    p = parser("a", "b", "c")
    @test runpeg(p, "abcd") == ( "a", "b", "c" )
    @test_throws ["ParseException","3", "c"] runpeg(p, "aboops")

    p = parser(oneof("cat", "dog"))
    @test runpeg(p, "catetonic") == "cat"
    @test runpeg(p, "dogma") == "dog"
    @test_throws ["ParseException", "1", "cat", "dog"] runpeg(p, "doh!")
    =#
    p = many(oneof("a", "b"))
    @test runpeg(p, "") == []
    @test runpeg(p, "abbabca") == ["a", "b", "b", "a", "b"]

    p = parser(r"a.*z")
    @test runpeg(p, "abc...z!") == "abc...z"
    @test_throws ["ParseException", "1"] runpeg(p, "zab")

    p = parser("The end.", END)
    @test runpeg(p, "The end.") == ("The end.", ())
    @test_throws ["ParseException", "9"] runpeg(p, "The end...")

    p = parser(
        oneof(
            r"\d+" => x -> parse(Int, x),
            ["nix", "nada"],
            "nix" => nothing,
            [not("backtrack"), r"\w+"] => Symbol ∘ last,
            "backtrack!"
        ),
        "." => ()
    )
    @test runpeg(p, "42.") == (42, ())
    @test runpeg(p, "nix.") == (nothing, ())
    @test runpeg(p, "cool.") == (:cool, ())
    @test runpeg(p, "backtrack!.") == ("backtrack!", ())
    @test_throws ["ParseException", "5"] runpeg(p, "oops!")

    maplast(vs) = map(last, vs)
    p = grammar(
        :expr => [:term,
            many("+", :term) => maplast
        ] => x -> sum([x[1], x[2]...]),
        :term => [:factor,
            many("*", :factor) => maplast
        ] => x -> prod([x[1], x[2]...]),
        :factor => oneof(:number, ["(", :expr, ")"] => x -> x[2]),
        :number => r"\d+" => v -> parse(Int, v),
    )
    @test runpeg(p, "2+3*4+5") == 19

    @testset "left-recursive" begin
        p = grammar(
            :start => [:as, END] => first,
            :as => oneof(
                [:as, "a"] => r -> r[1] * "a",
                "a")
        )
        @test p("aaa") == "aaa"

        sp = r"\s*"
        toylang = grammar(
            :start => [sp, :expr, END] => x -> x[2],
            :expr => oneof(
                [:var, "=", sp, :expr] => x -> ("=", first(x), last(x)),
                :term),
            :term => oneof(
                [:term, oneof("+", "-"), sp, :prod] => x -> (x[2], x[1], x[4]),
                :prod),
            :prod => oneof(
                [:prod, oneof("*", "/"), sp, :prim] => x -> (x[2], x[1], x[4]),
                :prim),
            :prim => oneof(
                ["-", :prim] => x -> ("neg", last(x)),
                ["(", sp, :exp, ")", sp] => x -> x[3],
                :var,
                :number),
            :number => [r"[[:digit:]]+", sp] => x -> parse(Int, first(x)),
            :var => [r"[_[:alpha:]][_[:alpha:][:digit:]]*", sp] => Symbol ∘ first,
        )
        @test toylang("a = b = c + d*e - f") == ("=", :a, ("=", :b, ("-", ("+", :c, ("*", :d, :e)), :f)))
    end

    @testset "macro syntax" begin

        g = @grammar begin
            start = [as !anych()] # without an action & a single named exprresion,
            # the result is un-tupled.
            as = [as "a" {as * "a"}; "a"]
        end
        @test g(repeat("a", 3)) == repeat("a", 3)

        g = @grammar begin
            start = [
                space expr !anych() {expr}
            ]
            expr = [
                expr "+" space term {expr + term}
                expr "-" space term {expr - term}
                term
            ]
            term = [
                term "*" space prim {term * prim}
                term "/" space prim {term / prim}
                prim
            ]
            prim = [
                number _:space # "_:" un-names the expression
                "(" expr ")"
            ]
            number = [
                D:anych("[:digit:]") DS:(anych("[:digit:]")...) {parse(Int, *(D, DS...))}
            ]
            space = many(anych("[:space:]"))
        end
        @test g("1+2*3+10/2 - 4") == 8
    end

    @testset "LookAhead" begin
        p = @peg([r:"hello" followedby(" ")])
        @test p("hello world") == "hello"
        @test_throws ["ParseException"] p("hello!")
    end
end
