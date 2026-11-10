# julia --project=. --threads=1 --startup-file=no experiments/performance/property_cost_sweep.jl OUTPUT.jsonl [TASKS_PER_DOMAIN] [DOMAIN[:MAX_COST]...]
using JSON3, Random
include("../src/Experiments.jl")
const P = Experiments.Phalcon
const COSTS = (strings=1:3, bitvectors=1:3, arc=1:2)
const SEED = 42

function exhaust_properties(candidates, example_count, population_size, enumerated)
    yielded = 0
    discriminating = 0
    best_agreement = nothing
    first_singleton_evaluation = nothing
    for candidate in candidates
        yielded += 1
        target, samples = P._property_values(candidate, example_count)
        agreement = count(values == target for values in samples)
        if 0 < agreement < population_size
            discriminating += 1
        end
        if agreement > 0 && (isnothing(best_agreement) || agreement < best_agreement)
            best_agreement = agreement
            if agreement == 1
                first_singleton_evaluation = enumerated[]
            end
        end
    end
    return (; yielded, discriminating, best_agreement, first_singleton_evaluation)
end

function sweep_task(record, domain, index, task, config, adapter, costs)
    problem, grammar = task
    test_indices = first(Experiments.evaluation_folds(config, problem))
    train, _, _ = Experiments.split_problem(problem, test_indices)
    benchmark = adapter.benchmark
    iterator = P.GeneticIterator(grammar, :Start; benchmark, problem=train,
        rng=Xoshiro(SEED), cost=_ -> 0, population_size=20,
        candidate_pool_size=adapter.candidate_pool_size, max_generations_without_improvement=10,
        max_extension_size=1, max_initial_population_size=1, max_size=50,
        rule_costs=Int[adapter.rule_cost(rule) for rule in grammar.rules])
    P.initialize!(iterator)
    solution = P.find_solution(iterator)
    common = (; domain, index, task=problem.name, train_examples=length(train.spec), test_indices,
        population=length(iterator.population))
    if !isnothing(solution)
        record(merge(common, (; status="solved_before_properties")))
        return
    end

    outputs = P.local_optimum_outputs(iterator)
    options = adapter.property_options
    property_grammar = get(options, :grammar_to_property_grammar, P._grammar_to_property_grammar)(grammar)
    rule_costs = Int[adapter.rule_cost(rule) for rule in property_grammar.rules]
    interpreter = Experiments.HerbInterpret.make_output_interpreter(property_grammar;
        target_module=benchmark, cache_module=benchmark)

    for max_cost in costs
        println(stderr, "$domain / $(problem.name) / max cost $max_cost")
        GC.gc()
        enumerated = Ref(0)
        stats = @timed begin
            candidates = P._property_candidates(; benchmark, problem=train, grammar=property_grammar,
                local_optimum_outputs=outputs, property_types=options.property_types,
                max_cost, rule_costs, interpreter, properties_enumerated=enumerated,
                max_output_bytes=get(options, :max_output_bytes, typemax(Int)))
            exhaust_properties(candidates, length(train.spec), length(outputs), enumerated)
        end
        record(merge(common, (; status="exhausted", max_cost, evaluated=enumerated[],
            seconds=stats.time, compile_seconds=stats.compile_time, gc_seconds=stats.gctime,
            allocated_bytes=stats.bytes), stats.value))
    end
end

function main(path, tasks_per_domain, domain_costs)
    tasks_per_domain > 0 || throw(ArgumentError("TASKS_PER_DOMAIN must be positive"))
    mkpath(dirname(abspath(path)))
    open(path, "w") do io
        record(row) = begin
            line = JSON3.write(row)
            println(io, line)
            flush(io)
            println(line)
            flush(stdout)
        end
        record((; kind="metadata", seed=SEED, julia=string(VERSION), threads=Threads.nthreads(),
            tasks_per_domain, costs=Dict(domain_costs)))
        for (domain, costs) in domain_costs
            config = Experiments.ExperimentConfig(benchmark=domain, seed=SEED, store=false)
            adapter = Experiments.benchmark_adapter(domain)
            tasks = Experiments.benchmark_tasks(config, adapter)
            sample_size = min(tasks_per_domain, length(tasks))
            indices = sample_size == 1 ? [1] : round.(Int, range(1, length(tasks); length=sample_size))
            for index in indices
                try
                    sweep_task(record, domain, index, tasks[index], config, adapter, costs)
                catch err
                    err isa InterruptException && rethrow()
                    record((; domain, index, task=tasks[index].problem.name, status="error",
                        error=sprint(showerror, err, catch_backtrace())))
                end
            end
        end
    end
end

function domain_costs(arg)
    parts = split(arg, ':'; limit=2)
    domain = Symbol(parts[1])
    default_costs = COSTS[domain]
    costs = length(parts) == 1 ? default_costs : 1:parse(Int, parts[2])
    isempty(costs) && throw(ArgumentError("MAX_COST must be positive"))
    return domain => costs
end

main(ARGS[1], length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 10,
    length(ARGS) >= 3 ? domain_costs.(ARGS[3:end]) : pairs(COSTS))
