using BenchmarkTools, Peggy

include("examples.jl")

input = read(open("test/bench-in.txt"), String)

@benchmark runpeg(peg_grammar, input)
