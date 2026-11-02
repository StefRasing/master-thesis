"""Print the useful outcome of a trial without archival metadata."""
function display_result(io::IO, result; repetition=1, repetitions=1)
    label = repetitions > 1 ? " (repetition $repetition/$repetitions)" : ""
    println(io, "\n", result["problem_name"], label)
    println(io, "  Training: ", result["solved_train_examples"] ? "solved" : "unsolved",
        "  |  Test: ", result["solved_test_examples"] ? "solved" : "unsolved")
    println(io, "  Time: ", round(result["execution_time"]; digits=3),
        " s  |  Programs evaluated: ", result["programs_enumerated"])
    solution = result["solution"]
    println(io, "  Solution: ", isnothing(solution) ? "none" : solution)
end

function output_path(config)
    !isnothing(config.output) && return config.output
    stem = "$(config.algorithm)_$(config.benchmark)"
    root = joinpath(@__DIR__, "..", "..", "data")
    config.benchmark == :arc && return joinpath(root, stem, "$(stem)_$(config.run)$(something(config.shard, "")).runs")
    config.algorithm == :heuristic && return joinpath(root, "$(stem)_20.runs")
    return joinpath(root, stem, "$(stem)$(config.run).runs")
end

function split_problem(problem, test_indices)
    isempty(test_indices) && throw(ArgumentError("test_indices cannot be empty"))
    all(i -> i in eachindex(problem.spec), test_indices) || throw(ArgumentError("invalid test index"))
    train_indices = setdiff(eachindex(problem.spec), test_indices)
    isempty(train_indices) && throw(ArgumentError("split leaves no training examples for $(problem.name)"))
    return Problem(problem.name, problem.spec[train_indices]), Problem(problem.name, problem.spec[test_indices]), train_indices
end

function run_trial(config, adapter, problem, grammar; rng=Random.Xoshiro(config.seed))
    train, test, train_indices = split_problem(problem, config.test_indices)
    # Keep unsupported string problems in the results, as in the original runners.
    supported = config.algorithm != :heuristic || config.benchmark != :strings || grammar.rules[1] == :ntString
    solution = nothing
    result = OrderedDict{String,Any}("problem_name"=>problem.name, "solved_train_examples"=>false,
        "solution"=>nothing, "programs_enumerated"=>0, "execution_time"=>0.0)
    if supported
        options = merge((benchmark=adapter.benchmark, problem=train,
            cost=config.algorithm == :phalcon ? (_ -> 0) : (pairs -> sum(adapter.distance(y, t) for (y,t) in pairs)),
            population_size=20, candidate_pool_size=adapter.candidate_pool_size,
            max_generations_without_improvement=config.algorithm == :phalcon ? 10 : 4,
            max_extension_size=1, max_initial_population_size=1, max_size=50,
            rule_costs=Int[adapter.rule_cost(r) for r in grammar.rules]), config.iterator_options)
        iterator = GeneticIterator(grammar, :Start; options..., rng)
        effective_iterator = config.store ? Dict(string(k)=>json_value(v) for (k,v) in pairs(options) if k != :problem) : nothing
        effective_phalcon = nothing
        if config.algorithm == :phalcon
            options = merge((max_number_of_properties=20, rule_cost_func=adapter.rule_cost,
                verbose=false, timeout=1800), adapter.property_options, config.phalcon_options)
            effective_phalcon = config.store ? json_value(options) : nothing
            solution, result = phalcon(; iterator, options...)
        else
            start = time()
            initialize!(iterator)
            solution = find_solution(iterator)
            result["execution_time"] = time() - start
            result["programs_enumerated"] = iterator.programs_evaluated
            result["solved_train_examples"] = !isnothing(solution)
            result["solution"] = isnothing(solution) ? nothing : string(rulenode2expr(solution, grammar))
        end
    end
    config.store && (result["effective_configuration"] = supported ? Dict("iterator"=>effective_iterator, "phalcon"=>effective_phalcon) : nothing)
    result["train_test_split"] = (train_indices, config.test_indices)
    result["solved_test_examples"] = !isnothing(solution) &&
        HerbInterpret.make_interpreter(grammar; target_module=adapter.benchmark, cache_module=adapter.benchmark)(solution, test.spec) == [io.out for io in test.spec]
    return result
end

function run_experiment(config::ExperimentConfig; io::IO=stdout)
    config.algorithm in (:phalcon, :heuristic) || throw(ArgumentError("unknown algorithm"))
    config.repetitions > 0 || throw(ArgumentError("repetitions must be positive"))
    adapter = benchmark_adapter(config.benchmark)
    RuntimeGeneratedFunctions.init(adapter.benchmark)
    tasks = benchmark_tasks(config, adapter)
    path = output_path(config)
    config.seed >= 0 || throw(ArgumentError("seed must be nonnegative"))
    haskey(config.iterator_options, :rng) && throw(ArgumentError("set config.seed instead of iterator_options.rng"))
    config.store && isfile(path) && throw(ArgumentError("choose a run directory, not a legacy JSON file"))
    if config.store
        validate_config_value(config.iterator_options)
        validate_config_value(config.phalcon_options)
    end
    provenance = config.store ? run_provenance() : nothing
    provenance_hash = config.store ? save_provenance(path, provenance) : nothing
    configuration = config.store ? Dict(string(k) => json_value(getfield(config, k)) for k in fieldnames(ExperimentConfig)
        if !(k in (:output, :store, :repetitions))) : nothing
    results = Any[]
    !config.store && println(io, "$(config.algorithm) · $(config.benchmark) · $(length(tasks)) problems · $(config.repetitions) repetitions")
    for (problem, grammar) in tasks
        for repetition in 1:config.repetitions
            # Independent streams: resume/order/sharding do not consume other runs' RNG state.
            seed_key = Dict("seed"=>config.seed, "run"=>config.run, "problem"=>problem.name, "repetition"=>repetition)
            seed = parse(UInt64, fingerprint(seed_key)[1:16]; base=16)
            if !config.store
                result = run_trial(config, adapter, problem, grammar; rng=Random.Xoshiro(seed))
                display_result(io, result; repetition, repetitions=config.repetitions)
                push!(results, result)
                continue
            end
            identity = Dict("problem"=>problem.name, "configuration"=>configuration,
                "seed"=>string(seed), "repetition"=>repetition,
                "provenance_sha256"=>provenance_hash)
            config.store && completed_run(path, identity) && continue
            started = string(now(UTC))
            result = run_trial(config, adapter, problem, grammar; rng=Random.Xoshiro(seed))
            record = Dict("schema_version"=>3, "run_id"=>fingerprint(identity),
                "identity"=>identity, "rng"=>"Random.Xoshiro", "provenance_sha256"=>provenance_hash,
                "started_at_utc"=>started, "completed_at_utc"=>string(now(UTC)), "result"=>result)
            append_result(path, record)
            push!(results, record)
        end
    end
    if !config.store && !isempty(results)
        train_solved = count(r -> r["solved_train_examples"], results)
        test_solved = count(r -> r["solved_test_examples"], results)
        println(io, "\nCompleted $(length(results)) trials · Training solved: $train_solved/$(length(results)) · Test solved: $test_solved/$(length(results))")
    end
    return results
end
