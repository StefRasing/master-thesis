using Pkg
Pkg.activate(joinpath(@__DIR__, "..", ".."))
include("../src/Experiments.jl")
Experiments.main(vcat(["phalcon", "bitvectors"], ARGS))
