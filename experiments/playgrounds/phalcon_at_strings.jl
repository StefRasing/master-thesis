using Pkg
let project_dir = normpath(joinpath(@__DIR__, "..", ".."))
    if Base.active_project() != joinpath(project_dir, "Project.toml")
        Pkg.activate(project_dir)
    end
end
if !isdefined(@__MODULE__, :Experiments)
    include("../src/Experiments.jl")
end

playground_results = let
    thresholds = (20)  # Keep 1 for the Phalcon baseline.
    problem_indices = 1:1  # Set to nothing to use the full strings suite.
    repetitions = 1  # Independent attempts per fold and threshold.
    timeout = 10  # Seconds per attempt.
    seed = 1
    verbose = false  # Set to true to print selected properties and their agreement.

    results = Dict{Int,Vector{Any}}()
    for agreement_threshold in thresholds
        label = agreement_threshold == 1 ? "Phalcon" : "Phalcon-AT($agreement_threshold)"
        println("\n$label (agreement threshold $agreement_threshold)")
        results[agreement_threshold] = Experiments.run_experiment(Experiments.ExperimentConfig(;
            algorithm=:phalcon, benchmark=:strings, store=false, problem_indices, repetitions, timeout, seed, verbose,
            phalcon_options=(; agreement_threshold)))
    end
    results
end

# Inspect playground_results by threshold in the REPL.
nothing
