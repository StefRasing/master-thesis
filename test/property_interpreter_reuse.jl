@testset "Property interpreter reuse keeps task state fresh" begin
    grammar = @csgrammar begin
        Start = _arg_out > 2
        Start = _arg_out > 1
    end
    interpreter = HerbInterpret.make_output_interpreter(grammar; target_module=Main, cache_module=Main)
    counter = Ref(0)
    total_candidates = 0
    for (target, outputs) in ((0, [[1], [2], [3], [4]]),
                              (3, [[4], [2], [1], [0]]),
                              (0, [[1], [2], [3], [4]]))
        input = Dict{Symbol,Any}(:_arg_1 => 123)
        options = (benchmark=Main, grammar=grammar,
            problem=(spec=[IOExample(input, target)],), local_optimum_outputs=outputs,
            property_types=[:Start], max_cost=1, rule_costs=[1, 1])
        fresh_count = Ref(0)
        fresh = find_property!(; options..., properties_enumerated=fresh_count)
        reused = find_property!(; options..., interpreter, properties_enumerated=counter)
        @test reused.program == fresh.program
        @test reused.target_values == fresh.target_values
        @test reused.agreement == fresh.agreement
        total_candidates += fresh_count[]
        @test counter[] == total_candidates
        @test input == Dict{Symbol,Any}(:_arg_1 => 123)
        @test isnothing(find_property!(; options..., interpreter, prune_node_by_output=_ -> true))
        @test find_property!(; options..., interpreter).target_values == fresh.target_values
    end
    # Reusing code must not bypass a deadline or inherit the previous enumeration bank.
    @test_throws Phalcon.SearchTimeout find_property!(benchmark=Main, grammar=grammar,
        problem=(spec=[IOExample(Dict{Symbol,Any}(), 0)],),
        local_optimum_outputs=[[1], [2]], property_types=[:Start], max_cost=1,
        rule_costs=[1, 1], interpreter=interpreter, deadline=Phalcon._search_time() - 1)
end
