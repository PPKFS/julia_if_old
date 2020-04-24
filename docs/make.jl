using Documenter, InteractiveFiction

makedocs(;
    modules=[InteractiveFiction],
    format=Documenter.HTML(),
    pages=[
        "Home" => "index.md",
    ],
    repo="https://github.com/PPKFS/InteractiveFiction.jl/blob/{commit}{path}#L{line}",
    sitename="InteractiveFiction.jl",
    authors="Avery",
    assets=String[],
)
