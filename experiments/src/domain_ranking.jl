function domain_property_grammar(tasks, adapter)
    if haskey(adapter.property_options, :grammar_to_property_grammar)
        return adapter.property_options.grammar_to_property_grammar(first(tasks).grammar)
    end

    # Drop task-specific constants and preserve the types of literal productions.
    productions(grammar) = [(type, typeof(rule), rule)
        for (type, rule) in zip(grammar.types, grammar.rules) if !isnothing(type)]
    shared = intersect(map(t -> productions(t.grammar), tasks)...)
    output_types = unique(t.grammar.rules[1] isa Symbol && t.grammar.rules[1] in t.grammar.types ?
        t.grammar.rules[1] : :Start for t in tasks)
    # Start aliases are task-specific when a suite has multiple return types.
    filter!(p -> p[1] != :Start || :Start in output_types, shared)
    assignments = [Expr(:(=), type, rule) for (type, _, rule) in shared]
    for type in output_types
        push!(assignments, Expr(:(=), type, :_arg_out))
    end
    return HerbGrammar.expr2csgrammar(Expr(:block, assignments...))
end

"""Select the task's holdout for this ranking round, cycling shorter fold lists."""
function domain_ranking_holdout(config, problem, round)
    folds = evaluation_folds(config, problem)
    return folds[mod1(round, length(folds))]
end

function prepare_domain_ranking(config, adapter, tasks, grammar, fold; program_interpreters=Dict(), settings=config.phalcon_options)
    training_tasks = map(tasks) do task
        holdout = domain_ranking_holdout(config, task.problem, fold)
        train, _, _ = trial_split(config, task.problem, holdout)
        return (problem=train, grammar=task.grammar)
    end
    options = merge((property_types=adapter.property_options.property_types,
        rule_cost_func=adapter.rule_cost,
        population_size=get(config.iterator_options, :population_size, 20),
        max_output_bytes=get(adapter.property_options, :max_output_bytes, 21 * 1024^2),
        timeout=config.timeout), settings)
    ranking_options = Base.structdiff(options, (max_number_of_properties=nothing,))
    return rank_domain_properties(training_tasks; grammar, benchmark=adapter.benchmark, program_interpreters, ranking_options...)
end

function domain_ranking_report(ranking, tasks, fold)
    return Dict("fold"=>fold, "properties_enumerated"=>ranking.enumerated,
        "sample_sizes"=>Dict(task.problem.name=>size for (task, size) in zip(tasks, ranking.sample_sizes)),
        "ranking"=>[(property=string(rulenode2expr(program, ranking.grammar)), agreement=score,
            enumeration_index=index) for (program, score, index) in ranking.ranked])
end

domain_ranking_file(path, benchmark, fold) = joinpath(path, "$(benchmark)_fold_$(fold).json")

function domain_ranking_context(config, tasks, grammar, fold)
    return Dict("benchmark"=>string(config.benchmark), "fold"=>fold,
        "grammar"=>[(string(type), repr(rule), string.(children))
            for (type, rule, children) in zip(grammar.types, grammar.rules, grammar.childtypes)],
        "constraints"=>repr(grammar.constraints),
        "tasks"=>[(name=task.problem.name, holdout=domain_ranking_holdout(config, task.problem, fold),
            examples=[(input=[(string(k), repr(ex.in[k])) for k in sort!(collect(keys(ex.in)))],
                output=repr(ex.out)) for ex in task.problem.spec]) for task in tasks])
end

encode_property_tree(node) = [get_rule(node), [encode_property_tree(child) for child in get_children(node)]]
decode_property_tree(tree) = RuleNode(Int(tree[1]), RuleNode[decode_property_tree(child) for child in tree[2]])

function full_domain_tasks(config, adapter)
    return benchmark_tasks(ExperimentConfig(; algorithm=:phalcon_domain, benchmark=config.benchmark), adapter)
end

"""Build and save domain rankings independently of synthesis."""
function run_domain_ranking(config::ExperimentConfig; fold::Union{Nothing,Int}=nothing, io::IO=stdout)
    config.algorithm == :phalcon_domain || throw(ArgumentError("set algorithm=:phalcon_domain"))
    isnothing(config.ranking_path) && throw(ArgumentError("set ranking_path to the output directory"))
    adapter = benchmark_adapter(config.benchmark)
    RuntimeGeneratedFunctions.init(adapter.benchmark)
    tasks = full_domain_tasks(config, adapter)
    grammar = domain_property_grammar(tasks, adapter)
    rounds = 1:maximum(length(evaluation_folds(config, task.problem)) for task in tasks)
    isnothing(fold) || fold in rounds || throw(ArgumentError("ranking fold must be in $rounds"))
    settings = merge((method=:friedman, population_size=100,
        max_property_evaluations=Phalcon.DEFAULT_MAX_PROPERTY_EVALUATIONS), config.phalcon_options)
    validate_config_value(settings)
    interpreters = Dict()
    return map(isnothing(fold) ? rounds : (fold,)) do round
        context = domain_ranking_context(config, tasks, grammar, round)
        request = fingerprint((; context, settings))
        destination = domain_ranking_file(config.ranking_path, config.benchmark, round)
        if !isfile(destination)
            println(io, "Ranking $(config.benchmark), fold $round ($(length(tasks)) problems)")
            ranking = prepare_domain_ranking(config, adapter, tasks, grammar, round;
                program_interpreters=interpreters, settings)
            report = domain_ranking_report(ranking, tasks, round)
            report["schema_version"] = 1
            report["context_sha256"] = fingerprint(context)
            report["request_sha256"] = request
            report["benchmark"] = string(config.benchmark)
            report["ranking_method"] = string(ranking.method)
            report["settings"] = json_value(settings)
            report["ranking_seconds"] = ranking.duration
            report["heldout_indices_by_problem"] = Dict(task.problem.name =>
                domain_ranking_holdout(config, task.problem, round) for task in tasks)
            report["ranking"] = [merge(entry, (rule_tree=encode_property_tree(program),
                mean_friedman_rank=isempty(ranking.mean_ranks) ? nothing : ranking.mean_ranks[position]))
                for (position, (entry, (program, _, _))) in enumerate(zip(report["ranking"], ranking.ranked))]
            publish_json(destination, report)
        end
        report = JSON3.read(read(destination, String))
        report.request_sha256 == request ||
            throw(ArgumentError("ranking settings differ from $destination; choose a new ranking directory"))
        println(io, "Ready: $destination ($(length(report.ranking)) properties)")
        destination
    end
end

function load_domain_ranking(config, adapter, tasks, grammar, fold)
    source = domain_ranking_file(config.ranking_path, config.benchmark, fold)
    isfile(source) || throw(ArgumentError("missing ranking $source; run phalcon-domain-rank first"))
    contents = read(source)
    report = JSON3.read(contents)
    report.schema_version == 1 || throw(ArgumentError("unsupported ranking format in $source"))
    context = domain_ranking_context(config, tasks, grammar, fold)
    report.context_sha256 == fingerprint(context) ||
        throw(ArgumentError("benchmark data, grammar, or splits differ from $source"))
    count = get(config.phalcon_options, :max_number_of_properties, 20)
    count >= 0 || throw(ArgumentError("max_number_of_properties must be nonnegative"))
    ranked = Tuple{RuleNode,Int,Int}[]
    for entry in Iterators.take(report.ranking, count)
        tree = decode_property_tree(entry.rule_tree)
        string(rulenode2expr(tree, grammar)) == entry.property ||
            throw(ArgumentError("property tree differs from saved expression in $source"))
        push!(ranked, (tree, Int(entry.agreement), Int(entry.enumeration_index)))
    end
    output_interpreter = HerbInterpret.make_output_interpreter(grammar;
        target_module=adapter.benchmark, cache_module=adapter.benchmark)
    interpret = (rule, children, context) -> Phalcon._interpret_domain_rule(output_interpreter, rule, children, context)
    return (; grammar, benchmark=adapter.benchmark, interpret, ranked,
        enumerated=Int(report.properties_enumerated), duration=Float64(report.ranking_seconds),
        sha256=bytes2hex(sha256(contents)), file=source)
end
