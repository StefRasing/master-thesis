using Pkg
Pkg.activate(joinpath(@__DIR__, "..", ".."))
if !isdefined(@__MODULE__, :Experiments)
    include("../src/Experiments.jl")
end

playground_results = Experiments.run_experiment(Experiments.ExperimentConfig(algorithm=:phalcon, benchmark=:strings,
    store=true, task_names=["2171308", "11604909"], phalcon_options=(max_property_cost=2,)))

# Keep results available for inspection without the REPL dumping the return value.
nothing
