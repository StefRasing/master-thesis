"""Print the useful outcome of a trial without archival metadata."""
function display_result(io::IO, result; repetition=1, repetitions=1)
    label = repetitions > 1 ? " (repetition $repetition/$repetitions)" : ""
    println(io, "\n", result["problem_name"], label, " (fold $(result["fold"])/$(result["folds"]))")
    println(io, "  Training: ", result["solved_train_examples"] ? "solved" : "unsolved",
        "  |  Test: ", result["solved_test_examples"] ? "solved" : "unsolved")
    println(io, "  Time: ", round(result["execution_time"]; digits=3),
        " s  |  Program candidates: ", result["programs_enumerated"],
        "  |  Property candidates: ", result["properties_enumerated"])
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

"""Deterministic folds, shared across algorithms, runs and repetitions."""
function evaluation_folds(config, problem)
    n = length(problem.spec)
    n >= 2 || throw(ArgumentError("$(problem.name) needs at least two examples"))
    if !isnothing(config.test_indices)
        split_problem(problem, config.test_indices) # Validate explicit overrides.
        return [copy(config.test_indices)]
    elseif config.benchmark == :arc
        splits = HerbBenchmarks.ARC_AGI1.ARC_AGI1_TRAINING_SPLITS
        split = get(splits, Symbol(problem.name), nothing)
        isnothing(split) && throw(ArgumentError("no official ARC split for $(problem.name); provide test_indices explicitly"))
        split.train > 0 && split.test > 0 && split.train + split.test == n ||
            throw(ArgumentError("official ARC split does not match examples for $(problem.name)"))
        return [collect((split.train + 1):n)]
    elseif config.benchmark == :strings
        key = Dict("seed"=>config.seed, "problem"=>problem.name, "protocol"=>"cv5_v1")
        seed = parse(UInt64, fingerprint(key)[1:16]; base=16)
        indices = Random.randperm(Random.Xoshiro(seed), n)
        k = min(5, n)
        return [sort(indices[i:k:end]) for i in 1:k]
    end
    return [[1]] # Preserve the bitvector protocol.
end

function split_problem(problem, test_indices)
    isempty(test_indices) && throw(ArgumentError("test_indices cannot be empty"))
    all(i -> i in eachindex(problem.spec), test_indices) || throw(ArgumentError("invalid test index"))
    train_indices = setdiff(eachindex(problem.spec), test_indices)
    isempty(train_indices) && throw(ArgumentError("split leaves no training examples for $(problem.name)"))
    return Problem(problem.name, problem.spec[train_indices]), Problem(problem.name, problem.spec[test_indices]), train_indices
end

function run_trial(config, adapter, problem, grammar; rng=Random.Xoshiro(config.seed), interpreter_ref=Ref{Any}(nothing),
        test_indices=first(evaluation_folds(config, problem)), fold=1, folds=length(evaluation_folds(config, problem)))
    train, test, train_indices = split_problem(problem, test_indices)
    # Non-string outputs are a baseline limitation: retain these tasks as unsolved.
    supported = config.algorithm != :heuristic || config.benchmark != :strings || grammar.rules[1] == :ntString
    solution = nothing
    result = OrderedDict{String,Any}("problem_name"=>problem.name, "solved_train_examples"=>false,
        "solution"=>nothing, "programs_enumerated"=>0, "properties_enumerated"=>0, "execution_time"=>0.0)
    if supported
        options = merge((benchmark=adapter.benchmark, problem=train, interpreter=interpreter_ref[],
            cost=config.algorithm == :phalcon ? (_ -> 0) : (pairs -> sum(adapter.distance(y, t) for (y,t) in pairs)),
            population_size=20, candidate_pool_size=adapter.candidate_pool_size,
            max_generations_without_improvement=10,
            max_extension_size=1, max_initial_population_size=1, max_size=50,
            rule_costs=Int[adapter.rule_cost(r) for r in grammar.rules]), config.iterator_options)
        iterator = GeneticIterator(grammar, :Start; options..., rng)
        effective_iterator = config.store ? Dict(string(k)=>json_value(v) for (k,v) in pairs(options) if !(k in (:problem, :interpreter))) : nothing
        effective_phalcon = nothing
        if config.algorithm == :phalcon
            options = merge((max_number_of_properties=20, rule_cost_func=adapter.rule_cost,
                verbose=config.verbose, timeout=config.timeout), adapter.property_options, config.phalcon_options)
            effective_phalcon = config.store ? json_value(options) : nothing
            solution, result = phalcon(; iterator, options...)
        else
            start = time()
            deadline = Phalcon._search_time() + config.timeout
            try
                initialize!(iterator; deadline)
                solution = find_solution(iterator; deadline)
            catch err
                err isa Phalcon.SearchTimeout || rethrow()
            end
            result["execution_time"] = time() - start
            result["programs_enumerated"] = iterator.programs_evaluated
            result["solved_train_examples"] = !isnothing(solution)
            result["solution"] = isnothing(solution) ? nothing : string(rulenode2expr(solution, grammar))
        end
        interpreter_ref[] = iterator.interpreter
    end
    config.store && (result["effective_configuration"] = supported ? Dict("iterator"=>effective_iterator,
        "timeout"=>config.algorithm == :phalcon ? effective_phalcon["timeout"] : config.timeout,
        "phalcon"=>effective_phalcon) : nothing)
    result["fold"] = fold
    result["folds"] = folds
    result["train_test_split"] = (train_indices, test_indices)
    outputs = isnothing(solution) ? nothing :
        HerbInterpret.make_interpreter(grammar; target_module=adapter.benchmark, cache_module=adapter.benchmark)(solution, test.spec)
    result["test_examples"] = length(test.spec)
    result["correct_test_examples"] = isnothing(outputs) ? 0 : count(i -> outputs[i] == test.spec[i].out, eachindex(test.spec))
    result["solved_test_examples"] = result["correct_test_examples"] == length(test.spec)
    return result
end

"""Compile shared search paths using a fixed, task-independent synthetic workload.

Run on every invocation, including resume. Never share its search state or RNG.
"""
function warmup_search!(adapter, benchmark)
    grammar = @csgrammar begin
        Start = 1
        Start = 2
        Start = Start + Start
    end
    problem = Problem("timing-warmup", [IOExample(Dict{Symbol,Any}(), 99)])
    for algorithm in (:heuristic, :phalcon)
        iterator = GeneticIterator(grammar, :Start; benchmark=adapter.benchmark,
            problem, rng=Random.Xoshiro(0), cost=_ -> 1, rule_costs=[1, 1, 1],
            population_size=20, candidate_pool_size=4, max_extension_size=1,
            max_initial_population_size=3, max_generations_without_improvement=1)
        if algorithm == :heuristic
            initialize!(iterator)
            find_solution(iterator)
        else
            phalcon(; iterator, timeout=Inf, max_number_of_properties=1,
                property_types=[:Start], max_property_cost=1, rule_cost_func=_ -> 1)
        end
    end
    # Canonical representatives are independent of selected tasks, shard, order,
    # seed and resume position. Cover benchmark-specific output/property types.
    seen = Set{Symbol}()
    for (problem, grammar) in benchmark_tasks(ExperimentConfig(; benchmark), adapter)
        output_type = grammar.types[1]
        output_type in seen && continue
        push!(seen, output_type)
        sample = Problem("timing-types", problem.spec[1:1])
        property_grammar = get(adapter.property_options, :grammar_to_property_grammar,
            Phalcon._grammar_to_property_grammar)(grammar)
        find_property!(; benchmark=adapter.benchmark, problem=sample,
            grammar=property_grammar, local_optimum_outputs=[[sample.spec[1].out]],
            property_types=adapter.property_options.property_types, max_cost=1,
            rule_costs=Int[adapter.rule_cost(r) for r in property_grammar.rules],
            max_output_bytes=get(adapter.property_options, :max_output_bytes, 21 * 1024^2))
    end
    return nothing
end

"""Prepare a grammar interpreter outside measurement, discarding all search state.

Exercise the benchmark's types using the same bounded extension enumeration used
by initialization. Only the generated interpreter survives; populations, outputs,
counters and the private RNG do not pass to the measured trial.
"""
function prepare_interpreter(config, adapter, problem, grammar; test_indices=first(evaluation_folds(config, problem)))
    train, _, _ = split_problem(problem, test_indices)
    interpreter = HerbInterpret.make_output_interpreter(grammar;
        target_module=adapter.benchmark, cache_module=adapter.benchmark)
    iterator = GeneticIterator(grammar, :Start; benchmark=adapter.benchmark,
        problem=train, interpreter, rng=Random.Xoshiro(0), cost=_ -> 1,
        rule_costs=Int[adapter.rule_cost(r) for r in grammar.rules],
        max_extension_size=1, max_initial_population_size=1)
    initialize!(iterator)
    return interpreter
end

function run_experiment(config::ExperimentConfig; io::IO=stdout)
    config.algorithm in (:phalcon, :heuristic) || throw(ArgumentError("unknown algorithm"))
    config.timing_protocol == :warmed_v1 || throw(ArgumentError("unsupported timing protocol"))
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
    # Repeat preparation after resume; never rely on completed trials to warm Julia.
    isempty(tasks) || warmup_search!(adapter, config.benchmark)
    # Run-owned reuse of explicitly prepared, unchanged grammar interpreters.
    interpreters = IdDict{Any,Base.RefValue{Any}}()
    !config.store && println(io, "$(config.algorithm) · $(config.benchmark) · $(length(tasks)) problems · $(config.repetitions) repetitions")
    for (problem, grammar) in tasks
        interpreter_ref = config.reuse_interpreter ? get!(() -> Ref{Any}(nothing), interpreters, grammar) : nothing
        folds = evaluation_folds(config, problem)
        for (fold, test_indices) in enumerate(folds), repetition in 1:config.repetitions
            # Independent streams: resume/order/sharding do not consume other runs' RNG state.
            seed_key = Dict("seed"=>config.seed, "run"=>config.run, "problem"=>problem.name, "repetition"=>repetition, "fold"=>fold, "test_indices"=>test_indices)
            seed = parse(UInt64, fingerprint(seed_key)[1:16]; base=16)
            if !config.store
                ref = isnothing(interpreter_ref) ? Ref{Any}(nothing) : interpreter_ref
                if isnothing(ref[]) && !(config.algorithm == :heuristic && config.benchmark == :strings && grammar.rules[1] != :ntString)
                    ref[] = prepare_interpreter(config, adapter, problem, grammar; test_indices)
                end
                result = run_trial(config, adapter, problem, grammar; rng=Random.Xoshiro(seed),
                    interpreter_ref=ref, test_indices, fold, folds=length(folds))
                display_result(io, result; repetition, repetitions=config.repetitions)
                push!(results, result)
                continue
            end
            identity = Dict("problem"=>problem.name, "configuration"=>configuration,
                "seed"=>string(seed), "repetition"=>repetition, "fold"=>fold, "test_indices"=>test_indices,
                "provenance_sha256"=>provenance_hash)
            config.store && completed_run(path, identity) && continue
            ref = isnothing(interpreter_ref) ? Ref{Any}(nothing) : interpreter_ref
            if isnothing(ref[]) && !(config.algorithm == :heuristic && config.benchmark == :strings && grammar.rules[1] != :ntString)
                ref[] = prepare_interpreter(config, adapter, problem, grammar; test_indices)
            end
            started = string(now(UTC))
            result = run_trial(config, adapter, problem, grammar; rng=Random.Xoshiro(seed),
                    interpreter_ref=ref, test_indices, fold, folds=length(folds))
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
