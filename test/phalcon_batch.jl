@testset "Batch Phalcon ranks distinct agreement sets" begin
    grammar = @csgrammar begin
        Start = 1
        Start = 2
        Start = 3
        Start = 4
        Start = 5
        Start = 6
    end
    property_grammar = @csgrammar begin
        Start = _arg_out > 4
        Start = _arg_out > 5
        Start = _arg_out <= 5
        Start = _arg_out == 99 || _arg_out == 5
        Start = _arg_out == 99
    end
    make_iterator() = GeneticIterator(grammar, :Start; benchmark=Main,
        problem=(name="batch", spec=[IOExample(Dict{Symbol,Any}(), 99)]),
        cost=_ -> 0, rule_costs=ones(Int, 6), population_size=3, max_initial_population_size=1)
    options = (property_types=[:Start], max_property_evaluations=5, rule_cost_func=_ -> 1,
        grammar_to_property_grammar=_ -> property_grammar)

    iterator = make_iterator()
    solution, stats = phalcon_batch(; iterator, options..., max_number_of_properties=2, agreement_threshold=3)
    @test isnothing(solution)
    @test stats["property_sample_target"] == stats["property_sample_size"] == 6
    @test stats["properties_enumerated"] == 5
    @test stats["heuristic"] == [(string(rulenode2expr(RuleNode(i), property_grammar)), 1, i)
        for i in (2, 4)]
    @test iterator.population_size == length(iterator.population) == 3
    @test [iterator.cost([(y, 99)]) for y in (1, 5, 6)] == [2, 1, 1]

    # The broader set overlaps both singleton sets and still qualifies.
    _, stats = phalcon_batch(; iterator=make_iterator(), options..., max_number_of_properties=4)
    @test stats["property_sample_target"] == 12
    @test stats["property_sample_size"] == 6
    @test stats["properties_enumerated"] == 5
    @test stats["heuristic"] == [(string(rulenode2expr(RuleNode(i), property_grammar)), agreement, i)
        for (i, agreement) in ((2, 1), (4, 1), (1, 2))]

    iterator = make_iterator()
    _, stats = phalcon_batch(; iterator, options..., timeout=0)
    @test iterator.population_size == 3
    @test stats["property_sample_size"] == stats["programs_enumerated"] == 0
end
