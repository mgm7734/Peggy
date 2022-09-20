using Peggy

peggram = @grammar
    start = [
        spaces grammar not(anych())          { grammar }
    ]
    grammar = [
        p:production ps:many(production)    { Peggy.Grammar(p, ps...) }
    ]
    production = [
        identifier "=" spaces expr          { identifier => expr }
    ]

end