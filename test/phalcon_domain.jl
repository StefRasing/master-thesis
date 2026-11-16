@testset "Phalcon domain ranking and reuse" begin
    grammar = @csgrammar begin
        Start = 1
        Start = 2
        Start = 3
        Start = 4
    end
    properties = @csgrammar begin
        Start = Output > 3
        Start = isodd(Output)
        Start = Output > 2
        Start = Output > 0
        Start = Output >= 3
        Start = iseven(Output)
        Start = Output == 2 || Output > 4
        Output = _arg_out
    end
    task(name, target) = (problem=(; name, spec=[IOExample(Dict{Symbol,Any}(), target)]), grammar)
    tasks = [task("a", 5), task("b", 6)]
    options = (benchmark=Main, grammar=properties, property_types=[:Start],
        rule_cost_func=_ -> 1, population_size=3)
    # The first property agrees with neither sample. The next two have
    # totals 3 and 2 respectively. The cap excludes the fourth property.
    ranking = rank_domain_properties(tasks; options..., max_property_evaluations=3)
    @test ranking.sample_sizes == [3, 3]
    @test ranking.enumerated == 3
    @test [(get_rule(program), score, index) for (program, score, index) in ranking.ranked] == [(3, 2, 3), (2, 3, 2)]

    # One zero among two tasks is allowed and adds nothing to the score.
    split_tasks = [task("a", 5), task("b", 0)]
    ranking_zero = rank_domain_properties(split_tasks; options..., max_property_evaluations=4)
    @test only(score for (program, score, _) in ranking_zero.ranked if get_rule(program) == 4) == 3

    # Two zeros among three tasks exceed the threshold.
    majority_zero = rank_domain_properties([split_tasks; task("c", -1)]; options...,
        max_property_evaluations=4)
    @test all(entry -> get_rule(entry[1]) != 4, majority_zero.ranked)

    # Keep the first occurrence of a pattern. Equal scores can come from
    # different programs agreeing and must remain distinct.
    unique_ranking = rank_domain_properties(tasks; options..., max_property_evaluations=7)
    @test unique_ranking.enumerated == 7
    @test [(get_rule(program), score, index) for (program, score, index) in unique_ranking.ranked] ==
        [(3, 2, 3), (7, 2, 7), (2, 3, 2), (4, 6, 4)]

    for task in tasks
        iterator = GeneticIterator(task.grammar, :Start; benchmark=Main, task.problem,
            cost=_ -> 0, rule_costs=ones(Int, 4), population_size=3)
        _, stats = phalcon_domain(; iterator, ranking, max_number_of_properties=1)
        @test stats["properties_enumerated"] == 0
        @test only(stats["heuristic"])[2:3] == (2, 3)
        @test iterator.cost([(1, task.problem.spec[1].out)]) == 1
        @test iterator.cost([(3, task.problem.spec[1].out)]) == 0
    end
end
