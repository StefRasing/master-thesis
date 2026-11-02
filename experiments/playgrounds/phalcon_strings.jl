using Pkg
Pkg.activate(joinpath(@__DIR__, "..", ".."))
include("../src/Experiments.jl")
using .Experiments

run_experiment(ExperimentConfig(algorithm=:phalcon, benchmark=:strings,
    store=false, task_names=["2171308"], phalcon_options=(max_property_cost=2,)))
