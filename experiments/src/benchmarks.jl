"""Benchmark-specific selection, grammar, metric, and search defaults."""
function benchmark_adapter(kind::Symbol)
    if kind == :arc
        return (benchmark=HerbBenchmarks.ARC_AGI1,
            rule_cost=r -> r isa Expr && !(r.args[1] in [:objects, :asgrid]),
            distance=hamming_distance, candidate_pool_size=10000,
            property_options=(property_types=[:Grid, :Objects, :Object, :Indices, :IntContainer, :IntegerTuple, :Integer, :Boolean],
                max_property_cost=3,
                grammar_to_property_grammar=_ -> Phalcon._grammar_to_property_grammar(property_grammar_hodel),
                display_outputs=HerbBenchmarks.ARC_AGI1.visualize, max_output_bytes=21 * 1024^2))
    elseif kind == :strings || kind == :bitvectors
        strings = kind == :strings
        return (benchmark=strings ? HerbBenchmarks.PBE_SLIA_Track_2019 : HerbBenchmarks.PBE_BV_Track_2018,
            rule_cost=r -> r isa Expr, distance=strings ? levenshtein : hamming_distance,
            candidate_pool_size=2000,
            property_options=strings ? (property_types=[:ntString, :ntInt, :ntBool], max_property_cost=3, max_output_bytes=21 * 1024^2) :
                (property_types=[:Start], max_property_cost=3,))
    end
    throw(ArgumentError("unknown benchmark: $kind"))
end

function benchmark_tasks(config, adapter)
    benchmark = adapter.benchmark
    if config.benchmark == :arc
        problems = benchmark.training_problems()
        if !isnothing(config.shard)
            shards = Dict("a"=>1:100, "b"=>101:200, "c"=>201:300, "d"=>301:400)
            haskey(shards, config.shard) || throw(ArgumentError("ARC shard must be a, b, c, or d"))
            problems = problems[shards[config.shard]]
        end
        tasks = [(problem=p, grammar=benchmark.grammar_hodel) for p in problems]
    else
        isnothing(config.shard) || throw(ArgumentError("shards are only supported for ARC"))
        names_ = [String(s)[9:end] for s in names(benchmark; all=true) if startswith(String(s), "problem_")]
        filter!(names_) do name
            config.benchmark == :strings ? all(f -> !occursin(f, name), ["short", "long", "repeat", "small"]) :
                length(getfield(benchmark, Symbol("problem_", name)).spec) <= 10
        end
        if !isnothing(config.task_names)
            all(in(names_), config.task_names) || throw(ArgumentError("unknown or excluded task name"))
            names_ = config.task_names
        end
        tasks = [(problem=getfield(benchmark, Symbol("problem_", n)), grammar=getfield(benchmark, Symbol("grammar_", n))) for n in names_]
    end
    return tasks[config.problem_indices]
end

