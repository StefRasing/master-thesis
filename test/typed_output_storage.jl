# Run with julia --project=. test/typed_output_storage.jl.
# Use the sibling checkout without changing the thesis Manifest.toml.
pushfirst!(LOAD_PATH, normpath(joinpath(@__DIR__, "..", "..", "HerbInterpret.jl")))
using Test, SparseArrays, DataStructures, StatsBase
using HerbCore, HerbGrammar, HerbConstraints, HerbSearch, HerbSpecification, HerbInterpret
include("../src/PhalconModule.jl")
using .Phalcon
using .Phalcon: CachedRuleNode, RuleNodeWithRuleCounts, Individual,
    get_programs, assemble, _hash_outputs, interp, outputs_to_cost

module TypedStorageDSL
    maybe(x::Int) = x < 0 ? nothing : x
end

@testset "Typed outputs through search storage" begin
    g = @csgrammar begin
        Start = _arg_1
        Start = 1
        Start = Start + Start
        Start = maybe(Start)
    end
    examples = [IOExample(Dict{Symbol,Any}(:_arg_1=>x), x+1) for x in (2, -1, 4)]
    output = HerbInterpret.make_output_interpreter(g; target_module=TypedStorageDSL)
    bus = LazyCostBasedBus(g, [:Start], 3, ones(Int, 4),
        (r,c)->output(r,c,examples), isnothing)
    leaves = get_programs(bus, :Start, 1)
    input = only(filter(p->p.rule==1, leaves))
    one = only(filter(p->p.rule==2, leaves))
    @test input.outputs isa Vector{Int}
    @test one.outputs isa Vector{Int}
    sum_node = assemble(bus, 3, [input, one])
    @test sum_node.outputs isa Vector{Int}
    @test sum_node.outputs == [3, 0, 5]
    @test _hash_outputs(sum_node.outputs) == _hash_outputs(Any[3, 0, 5])
    @test assemble(bus, 3, [input, one]) === nothing # deduplication
    @test assemble(bus, 4, [input]) === nothing # pruning nothing

    iter = GeneticIterator(g, :Start; problem=(spec=examples,),
        cost=pairs->sum(abs(y-target) for (y,target) in pairs),
        rule_costs=ones(Int, 4), benchmark=TypedStorageDSL)
    iter.interpreter = output
    # Empty comprehensions can produce Any[], and heterogeneous collections
    # may erase the outer element type without erasing the child-vector types.
    @test interp(iter, 1, Any[]) == [2, -1, 4]
    @test interp(iter, 1, Any[]) isa Vector{Int}
    @test interp(iter, 3, Any[input.outputs, one.outputs]) == [3, 0, 5]
    @test interp(iter, 3, Any[input.outputs, one.outputs]) isa Vector{Int}
    initialized = GeneticIterator(g, :Start; problem=(spec=examples,),
        cost=pairs->sum(abs(y-target) for (y,target) in pairs),
        rule_costs=ones(Int, 4), benchmark=TypedStorageDSL)
    initialize!(initialized)
    @test !isempty(initialized.population)
    @test all(ind.program.outputs isa Vector{Int} for ind in initialized.population)
    genetic = RuleNodeWithRuleCounts(iter, sum_node)
    @test genetic.outputs === sum_node.outputs
    @test genetic.children[1].outputs === input.outputs
    rebuilt = RuleNodeWithRuleCounts(iter, 3, genetic.children)
    @test rebuilt.outputs isa Vector{Int}
    @test rebuilt.outputs == sum_node.outputs
    maybe = RuleNodeWithRuleCounts(iter, 4, [genetic.children[1]])
    @test maybe.outputs isa Vector{Union{Nothing,Int}}
    @test isequal(maybe.outputs, [2, nothing, 4])
    @test outputs_to_cost(iter, maybe.outputs) == Inf
    @test outputs_to_cost(iter, rebuilt.outputs) == -Inf
    push!(iter.population, Individual(iter, rebuilt))
    push!(iter.population, Individual(iter, maybe))
    local_outputs = local_optimum_outputs(iter)
    @test local_outputs[1] === rebuilt.outputs
    @test local_outputs[2] === maybe.outputs
    property = Property(RuleNode(1), rebuilt.outputs, 0.5)
    @test property.target_values === rebuilt.outputs
    # Property synthesis accepts both homogeneous and heterogeneous vector types.
    @test find_property!(benchmark=TypedStorageDSL, problem=(spec=examples,),
        grammar=g, local_optimum_outputs=local_outputs, property_types=[:Start],
        max_cost=0, rule_costs=ones(Int, 4), prune_node_by_output=isnothing) === nothing
    iter.prune_node_by_output = (io,y)->y===nothing || y<0
    @test interp(iter, 1, Vector[]) isa Vector{Nothing}

    # Different program-output types coexist in the same search bank.
    g2 = @csgrammar begin
        N = _arg_1
        S = string(N)
        B = N > 0
    end
    out2 = HerbInterpret.make_output_interpreter(g2)
    bus2 = LazyCostBasedBus(g2, [:N,:S,:B], 2, ones(Int, 3),
        (r,c)->out2(r,c,examples), isnothing)
    @test only(get_programs(bus2, :N, 1)).outputs isa Vector{Int}
    @test only(get_programs(bus2, :S, 2)).outputs isa Vector{String}
    @test only(get_programs(bus2, :B, 2)).outputs isa Vector{Bool}
end

@testset "Complete node output byte limit" begin
    g = @csgrammar begin
        Start = 1
    end
    examples = [IOExample(Dict{Symbol,Any}(), 1) for _ in 1:3]
    shared = collect(1:32)
    outputs = [shared, shared, shared]
    bytes = Base.summarysize(outputs)
    @test all(Base.summarysize(y) < bytes for y in outputs)
    @test bytes < sum(Base.summarysize, outputs) # shared contents counted once

    iter = GeneticIterator(g, :Start; problem=(spec=examples,),
        cost=_ -> 0, rule_costs=[1], max_output_bytes=bytes)
    iter.interpreter = (r, c, spec) -> outputs
    @test interp(iter, 1, Any[]) === outputs # equality is allowed
    iter.max_output_bytes = bytes - 1
    @test interp(iter, 1, Any[]) == fill(nothing, 3)
    iter.max_output_bytes = typemax(Int)
    @test interp(iter, 1, Any[]) === outputs

    bus = LazyCostBasedBus(g, [:Start], 1, [1], (r,c) -> outputs,
        _ -> error("Oversized outputs must be rejected before callbacks");
        max_output_bytes=bytes - 1)
    @test assemble(bus, 1, CachedRuleNode[]) === nothing
    @test isempty(bus.seen_outputs_hashes)
    accepted = LazyCostBasedBus(g, [:Start], 1, [1], (r,c) -> outputs,
        _ -> false; max_output_bytes=bytes)
    @test assemble(accepted, 1, CachedRuleNode[]).outputs === outputs
end

@testset "Phalcon uses the iterator's DSL module" begin
    # There is deliberately no global `benchmark` in the calling scope.
    g = @csgrammar begin
        Start = _arg_1
        Start = maybe(Start)
    end
    examples = [IOExample(Dict{Symbol,Any}(:_arg_1 => 2), 3)]
    iter = GeneticIterator(g, :Start;
        benchmark=TypedStorageDSL, problem=(name="module smoke test", spec=examples),
        cost=_ -> 0, rule_costs=[1, 1])
    solution, result = phalcon(iterator=iter, property_types=[:Start],
        max_property_cost=1, rule_cost_func=_ -> 1, timeout=0)
    @test solution === nothing
    @test result["problem_name"] == "module smoke test"
    @test result["solved_train_examples"] == false
    @test parentmodule(GeneticIterator) === Phalcon
end
