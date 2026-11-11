include("setup.jl")
include("output_limits.jl")
include("algorithm_contracts.jl")
include("phalcon_batch.jl")
include("property_interpreter_reuse.jl")
include("genetic_diagnostics.jl")
include("typed_output_storage.jl")
include("resumable_cost_based_bus.jl")
include("contains_cost_based_bus.jl")
include("selective_contains_cost_based_bus.jl")
include("string_property_ranking.jl")

@testset "Search termination and deadlines" begin
    g = @csgrammar begin
        Start = 1
    end
    make_iter(target) = GeneticIterator(g, :Start;
        problem=(name="leaf", spec=[IOExample(Dict{Symbol,Any}(), target)],),
        cost=_ -> 1, rule_costs=[1], benchmark=TypedStorageDSL)

    solved = make_iter(1)
    initialize!(solved)
    @test find_solution(solved) == RuleNode(1)
    @test_throws ArgumentError Phalcon.combine!(solved)

    unsolved = make_iter(2)
    initialize!(unsolved)
    @test_throws ArgumentError find_solution(unsolved)
    empty!(unsolved.population)
    @test_throws ArgumentError Phalcon.combine!(unsolved)

    expired = Phalcon._search_time() - 1
    @test_throws Phalcon.SearchTimeout initialize!(make_iter(2); deadline=expired)
    @test_throws Phalcon.SearchTimeout find_solution(solved; deadline=expired)
    bus = LazyCostBasedBus(g, [:Start], 1, [1], (_, _) -> error("must not evaluate"),
        isnothing; deadline=expired)
    @test_throws Phalcon.SearchTimeout get_programs(bus, :Start, 1)
    @test_throws Phalcon.SearchTimeout find_property!(benchmark=TypedStorageDSL,
        problem=solved.problem, grammar=g, local_optimum_outputs=[[1]],
        property_types=[:Start], max_cost=1, rule_costs=[1], deadline=expired)
    solution, stats = phalcon(iterator=make_iter(2), timeout=0,
        property_types=[:Start], max_property_cost=1, rule_cost_func=_ -> 1)
    @test solution === nothing
    @test stats["programs_enumerated"] == 0
    @test stats["properties_enumerated"] == 0
end

include("experiments.jl")

@testset "Property agreement threshold" begin
    grammar = @csgrammar begin
        Start = _arg_out > 4
        Start = _arg_out > 0
        Start = _arg_out > 2
        Start = _arg_out > 1
        Start = _arg_out > 3
    end
    options = (benchmark=TypedStorageDSL,
        problem=(spec=[IOExample(Dict{Symbol,Any}(), 0)],), grammar=grammar,
        local_optimum_outputs=[[1], [2], [3], [4]], property_types=[:Start],
        max_cost=2, rule_costs=[1, 1, 1, 2, 2])
    counter = Ref(0)
    @test find_property!(; options..., properties_enumerated=counter).agreement === 1
    default_count = counter[]
    @test isnothing(find_property!(; options..., properties_enumerated=counter,
        prune_node_by_output=_ -> true))
    @test counter[] > default_count

    counter[] = 0
    property = find_property!(; options..., agreement_threshold=2, properties_enumerated=counter)
    @test property.agreement === 2
    @test property.program == RuleNode(3)
    @test counter[] < default_count

    # The last positive match has agreement 4, but the best match has 2.
    fallback = find_property!(; options..., rule_costs=[2, 1, 1, 3, 3])
    @test fallback.agreement === 2
    @test fallback.program == RuleNode(3)
    @test_throws ArgumentError find_property!(; options..., agreement_threshold=0)
end

@testset "Property enumeration results accumulate across searches" begin
    grammar = @csgrammar begin
        Start = 1
        Start = 2
    end
    property_grammar = @csgrammar begin
        Start = _arg_out > 0
        Start = _arg_out > 1
    end
    iter = GeneticIterator(grammar, :Start; benchmark=Main,
        problem=(name="property-counts", spec=[IOExample(Dict{Symbol,Any}(), 99)],),
        cost=_ -> 0, rule_costs=[1, 1], max_initial_population_size=1,
        max_generations_without_improvement=0)
    _, stats = phalcon(; iterator=iter, property_types=[:Start], agreement_threshold=2,
        max_property_evaluations=1, rule_cost_func=r -> r == :(_arg_out > 0) ? 1 : 2,
        max_number_of_properties=2,
        grammar_to_property_grammar=_ -> property_grammar)
    @test stats["programs_enumerated"] == 2
    @test stats["properties_enumerated"] == 2
    @test [(agreement, index) for (_, agreement, index) in stats["heuristic"]] == [(2, 1), (2, 1)]
end

@testset "Property evaluation budget" begin
    grammar = @csgrammar begin
        Start = 1
        Start = 2
        Start = 3
        Start = 4
    end
    calls = Int[]
    outputs = [[0, 0, 0, 1], [0, 0, 0, 1], fill(nothing, 4), [0, 0, 1, 1]]
    interpreter = (rule, children, specs) -> (push!(calls, rule); outputs[rule])
    counter = Ref(8)
    options = (benchmark=Main, grammar=grammar,
        problem=(spec=[IOExample(Dict{Symbol,Any}(), 0)],),
        local_optimum_outputs=[[1], [2], [3]], property_types=[:Start],
        rule_costs=fill(5, 4), prune_node_by_output=isnothing,
        interpreter=interpreter, properties_enumerated=counter)

    best = find_property!(; options..., max_property_evaluations=3)
    @test best.program == RuleNode(1)
    @test best.agreement == 2
    @test best.enumeration_index == 1
    @test calls == [1, 2, 3] # A duplicate and a pruned candidate both count.
    @test counter[] == 11

    empty!(calls)
    best = find_property!(; options..., max_property_evaluations=4)
    @test best.program == RuleNode(4)
    @test best.agreement == 1
    @test best.enumeration_index == 4
    @test calls == [1, 2, 3, 4]
    @test counter[] == 15
    @test isnothing(find_property!(; options..., max_property_evaluations=0))
    @test counter[] == 15
    @test_throws ArgumentError find_property!(; options..., max_property_evaluations=-1)

    nested = @csgrammar begin
        Start = identity(Child)
        Child = 1
        Child = 2
    end
    empty!(calls)
    nested_options = merge(options, (grammar=nested, rule_costs=[1, 0, 0]))
    @test isnothing(find_property!(; nested_options..., max_property_evaluations=1))
    @test calls == [2] # Stop inside child-pool discovery before interpreting a parent.
    @test counter[] == 16

    unproductive = @csgrammar begin
        Start = identity(Start)
    end
    @test isnothing(find_property!(; merge(options, (grammar=unproductive, rule_costs=[1]))...))
    @test counter[] == 16
end
