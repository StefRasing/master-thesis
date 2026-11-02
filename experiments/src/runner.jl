function output_path(config)
    !isnothing(config.output) && return config.output
    stem = "$(config.algorithm)_$(config.benchmark)"
    root = joinpath(@__DIR__, "..", "..", "data")
    config.benchmark == :arc && return joinpath(root, stem, "$(stem)_$(config.run)$(something(config.shard, "")).json")
    config.algorithm == :heuristic && return joinpath(root, "$(stem)_20.json")
    return joinpath(root, stem, "$(stem)$(config.run).json")
end

function split_problem(problem, test_indices)
    isempty(test_indices) && throw(ArgumentError("test_indices cannot be empty"))
    all(i -> i in eachindex(problem.spec), test_indices) || throw(ArgumentError("invalid test index"))
    train_indices = setdiff(eachindex(problem.spec), test_indices)
    isempty(train_indices) && throw(ArgumentError("split leaves no training examples for $(problem.name)"))
    return Problem(problem.name, problem.spec[train_indices]), Problem(problem.name, problem.spec[test_indices]), train_indices
end

function run_trial(config, adapter, problem, grammar)
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
        iterator = GeneticIterator(grammar, :Start; options...)
        if config.algorithm == :phalcon
            options = merge((max_number_of_properties=20, rule_cost_func=adapter.rule_cost,
                verbose=false, timeout=1800), adapter.property_options, config.phalcon_options)
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
    result["train_test_split"] = (train_indices, config.test_indices)
    result["solved_test_examples"] = !isnothing(solution) &&
        HerbInterpret.make_interpreter(grammar; target_module=adapter.benchmark, cache_module=adapter.benchmark)(solution, test.spec) == [io.out for io in test.spec]
    return result
end

function run_experiment(config::ExperimentConfig)
    config.algorithm in (:phalcon, :heuristic) || throw(ArgumentError("unknown algorithm"))
    config.repetitions > 0 || throw(ArgumentError("repetitions must be positive"))
    adapter = benchmark_adapter(config.benchmark)
    RuntimeGeneratedFunctions.init(adapter.benchmark)
    tasks = benchmark_tasks(config, adapter)
    path = output_path(config)
    config.store && mkpath(dirname(path))
    results = Any[]
    for (problem, grammar) in tasks
        completed = config.store ? performed_repetitions(path, problem.name) : 0
        for _ in 1:max(0, config.repetitions - completed)
            result = run_trial(config, adapter, problem, grammar)
            config.store ? append_result(path, result) : println(result)
            push!(results, result)
        end
    end
    return results
end

