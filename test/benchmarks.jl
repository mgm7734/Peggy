using BenchmarkTools, Peggy

# include("examples.jl")

#input = read(open("test/bench-in.txt"), String)
#
#@benchmark peg_grammar(input)

badcalc = @peg begin 
    term = { 
        number "+" term           :> (number + term) 
        number "-" term           :> (number - term) 
        number 
    }
    number = { ds=CHAR("[:digit:]")+_  :> parse(Int, *(ds...))  }
end;

calc = @peg begin 
    term = { 
        term "+" number           :> (term + number) 
        term "-" number           :> (term - number) 
        number 
    }
    number = { ds=CHAR("[:digit:]")+_  :> parse(Int, *(ds...))  }
end;

# interestingly, left recursive version using MUCh less stack. badcalc blows up a ^1000. 
# calc handles ^5000
s = "10" * "+ 2 - 3"^100

@benchmark badcalc(s)

@benchmark calc(s)
