using Pkg
Pkg.activate(joinpath(@__DIR__, "..", ".."))
include("../src/Experiments.jl")
using .Experiments

run_experiment(ExperimentConfig(algorithm=:heuristic, benchmark=:strings,
    store=false, problem_indices=1:1))
