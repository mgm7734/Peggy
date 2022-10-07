using Peggy
using Documenter

#DocMeta.setdocmeta!(Peggy, :DocTestSetup, :(using Peggy); recursive=true)

makedocs(;
    modules=[Peggy],
    authors="Mark Mendel <mmendel@meinergy.com> and contributors",
    repo="https://github.com/mgm7734/Peggy.jl/blob/{commit}{path}#{line}",
    sitename="Peggy.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://mgm7734.github.io/Peggy.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
        "Expressions" => "expressions.md"
    ],
)

deploydocs(;
    repo="github.com/mgm7734/Peggy.jl",
    devbranch="main",
)
