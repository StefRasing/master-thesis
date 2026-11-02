include("typed_output_storage.jl")

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
end

include("experiments.jl")

@testset "Property stopping policies" begin
    grammar = @csgrammar begin
        Start = _arg_out > 2
        Start = _arg_out > 1
    end
    options = (benchmark=TypedStorageDSL,
        problem=(spec=[IOExample(Dict{Symbol,Any}(), 0)],), grammar=grammar,
        local_optimum_outputs=[[1], [2], [3], [4]], property_types=[:Start],
        max_cost=1, rule_costs=[1, 1])
    @test find_property!(; options...).reduction_rate == 0.75
    @test find_property!(; options..., stop_reduction_rate=0.5).reduction_rate == 0.5
    @test_throws ArgumentError find_property!(; options..., stop_reduction_rate=1.0)
end
