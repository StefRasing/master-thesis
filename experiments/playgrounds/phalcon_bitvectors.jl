using Pkg
Pkg.activate(joinpath(@__DIR__, "..", ".."))
if !isdefined(@__MODULE__, :Experiments)
    include("../src/Experiments.jl")
end

playground_results = Experiments.run_experiment(Experiments.ExperimentConfig(algorithm=:phalcon, benchmark=:bitvectors,
    store=true, problem_indices=1:5, verbose=true))

# Keep results available for inspection without the REPL dumping the return value.
nothing
