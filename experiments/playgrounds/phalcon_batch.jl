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
    algorithms = (:phalcon_batch,)  # Use (:phalcon_batch,) to run only the batch variant.
    problem_indices = 1:1  # First ARC training task, with its official train/test split.
    repetitions = 1
    seed = 1
    timeout = 30 * 60  # Seconds per attempt.
    verbose = true  # Set to true to print individual properties and their agreement.

    population_size = 20
    max_number_of_properties = 20  # Batch sample target = population size × property limit.
    max_property_evaluations = 10_000
    agreement_threshold = 1  # Early stopping for standard Phalcon.

    results = Dict{Symbol,Vector{Any}}()
    for algorithm in algorithms
        println()
        trials = Experiments.run_experiment(Experiments.ExperimentConfig(;
            algorithm, benchmark=:arc, store=true, problem_indices,
            repetitions, seed, timeout, verbose, iterator_options=(; population_size),
            phalcon_options=(; max_number_of_properties, max_property_evaluations, agreement_threshold)))
        results[algorithm] = trials
        if algorithm == :phalcon_batch
            for record in trials
                trial = get(record, "result", record)
                println("  ", trial["problem_name"], " (fold ", trial["fold"], ") · ",
                    "Sample: ", trial["property_sample_size"], "/", trial["property_sample_target"],
                    " · Selected properties: ", length(trial["heuristic"]), "/", max_number_of_properties)
            end
        end
    end
    results
end

# Inspect playground_results[:phalcon_batch] or playground_results[:phalcon] in the REPL.
nothing
