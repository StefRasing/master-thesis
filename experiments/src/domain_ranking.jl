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

function prepare_domain_ranking(config, adapter, tasks, grammar, fold; program_interpreters=Dict())
    training_tasks = map(tasks) do task
        folds = evaluation_folds(config, task.problem)
        train, _, _ = trial_split(config, task.problem, folds[fold])
        return (problem=train, grammar=task.grammar)
    end
    options = merge((property_types=adapter.property_options.property_types,
        rule_cost_func=adapter.rule_cost,
        population_size=get(config.iterator_options, :population_size, 20),
        max_output_bytes=get(adapter.property_options, :max_output_bytes, 21 * 1024^2),
        timeout=config.timeout), config.phalcon_options)
    ranking_options = Base.structdiff(options, (max_number_of_properties=nothing,))
    return rank_domain_properties(training_tasks; grammar, benchmark=adapter.benchmark, program_interpreters, ranking_options...)
end

function domain_ranking_report(ranking, tasks, fold)
    return Dict("fold"=>fold, "properties_enumerated"=>ranking.enumerated,
        "sample_sizes"=>Dict(task.problem.name=>size for (task, size) in zip(tasks, ranking.sample_sizes)),
        "ranking"=>[(property=string(rulenode2expr(program, ranking.grammar)), agreement=score,
            enumeration_index=index) for (program, score, index) in ranking.ranked])
end
