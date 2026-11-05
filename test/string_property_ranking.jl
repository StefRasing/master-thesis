# Standalone: julia --project=. test/string_property_ranking.jl
using Test, HerbGrammar, HerbSpecification
include("../experiments/research/rank_string_properties.jl")
const SPR = StringPropertyRanking

@testset "Domain property ranking" begin
    # Two examples per program: matching just one example does not count.
    @test SPR.acceptance_count([1, 2, 1, 2, 1, 9], 2, 2) == 1
    @test SPR.acceptance_count([1, 2, 1, 9, 0, 2], 2, 2) == 0
    @test SPR.acceptance_count([1, 2, nothing, 2, 1, 2], 2, 2) == 1
    @test isnothing(SPR.acceptance_count([nothing, 2, 1, 2], 2, 1))
    @test_throws DimensionMismatch SPR.acceptance_count([1], 2, 1)

    grammar = @csgrammar begin
        ntString = _arg_1
        ntString = _arg_out
        ntInt = len_cvc(ntString)
        ntBool = ntString == ntString
    end
    example(x, y) = IOExample(Dict{Symbol,Any}(:_arg_1 => x), y)
    tasks = [(problem=(name="a", spec=[example("source-a", "a"), example("source-b", "b")]), grammar=grammar),
             (problem=(name="b", spec=[example("source-c", "c"), example("source-d", "d")]), grammar=grammar)]
    samples = [(outputs=[ ["a", "b"], ["a", "x"] ],),
               (outputs=[ ["c", "x"], ["x", "d"] ],)]
    context = SPR.property_context(tasks[1], samples[1])
    @test length(context) == 6
    @test [c[:_arg_out] for c in context] == ["a", "b", "a", "b", "a", "x"]
    @test [c[:_arg_1] for c in context] == ["source-a", "source-b", "source-a", "source-b", "source-a", "source-b"]

    config = SPR.RankingConfig(programs=2, max_property_cost=1)
    result = SPR.rank_properties(tasks, samples, grammar, config; io=devnull)
    @test result.complete
    @test result.invalid_counts["zero_acceptance"] > 0
    # Identity gets acceptance 1 on the first task but 0 on the second: discard
    # it entirely, rather than recording its partial sum as a valid score.
    @test all(r["property"] != "_arg_out" for r in result.ranked)
    lengths = only(filter(r -> r["property"] == "len_cvc(_arg_out)", result.ranked))
    @test lengths["score"] == 4
    @test lengths["acceptance_by_task"] == [2, 2]
    @test any(r -> occursin("_arg_1", r["property"]), result.ranked)
    @test issorted([r["score"] for r in result.ranked])

    keep_zero = SPR.rank_properties(tasks, samples, grammar,
        SPR.RankingConfig(programs=2, max_property_cost=1, prune_zero_acceptance=false); io=devnull)
    identity = only(filter(r -> r["property"] == "_arg_out", keep_zero.ranked))
    @test identity["acceptance_by_task"] == [1, 0]
    @test identity["score"] == 1
    @test keep_zero.invalid_counts["zero_acceptance"] == 0
    @test length(keep_zero.ranked) > length(result.ranked)
    @test all(r in keep_zero.ranked for r in result.ranked)

    uncached = SPR.rank_properties(tasks, samples, grammar,
        SPR.RankingConfig(programs=2, max_property_cost=1, cache_bytes=0); io=devnull)
    @test result.ranked == uncached.ranked
    @test result.invalid_counts == uncached.invalid_counts
    evicting = SPR.rank_properties(tasks, samples, grammar,
        SPR.RankingConfig(programs=2, max_property_cost=1, cache_bytes=128); io=devnull)
    @test result.ranked == evicting.ranked
    @test result.invalid_counts == evicting.invalid_counts
    @test SPR.output_bytes_bound(["same", "same"]) >= Base.summarysize(["same", "same"])

    enumerated_properties = Tuple{String,Symbol,Int}[]
    SPR.foreach_property(grammar, 2) do program, type, cost
        push!(enumerated_properties, (string(HerbGrammar.rulenode2expr(program, grammar)), type, cost))
    end
    identities = [(expr, type) for (expr, type, cost) in enumerated_properties]
    @test length(identities) == length(unique(identities))
    @test [(expr, cost) for (expr, type, cost) in enumerated_properties if expr == "_arg_out"] == [("_arg_out", 0)]
    @test all(cost == 1 for (expr, type, cost) in enumerated_properties if expr == "len_cvc(_arg_out)")

    sampling_grammar = @csgrammar begin
        Start = _arg_1
        Start = "a"
        Start = "b"
    end
    sampling_task = (problem=(name="exclude_solution", spec=[example("x", "x")]), grammar=sampling_grammar)
    sampled = SPR.sample_programs(sampling_task, SPR.RankingConfig(programs=2, max_program_cost=0))
    @test length(sampled.outputs) == 2
    @test sampled.solutions_excluded == 1
    @test sampled.outputs == [["a"], ["b"]]
    @test all(outputs != ["x"] for outputs in sampled.outputs)

    # Shared constants distinguish literal Bool/Int; task-specific constants do
    # not leak into a supposedly shared grammar.
    g1 = @csgrammar begin
        Start = ntString
        ntString = _arg_1
        ntString = "task-specific"
        ntInt = 1
        ntBool = true
    end
    g2 = @csgrammar begin
        Start = ntString
        ntString = _arg_1
        ntString = "other"
        ntInt = 1
        ntBool = true
    end
    shared = SPR.shared_property_grammar([(grammar=g1,), (grammar=g2,)])
    @test !any(r -> r isa String, shared.rules)
    @test any(r -> r === 1, shared.rules)
    @test any(r -> r === true, shared.rules)
    @test :_arg_out in shared.rules
end

include("../experiments/research/filter_zero_score_properties.jl")
@testset "Filter zero total scores, preserving per-task zeros" begin
    zero = Dict("property" => "identity", "score" => 0, "acceptance_by_task" => [0, 0])
    partial = Dict("property" => "partial", "score" => 2, "acceptance_by_task" => [0, 2])
    positive = Dict("property" => "positive", "score" => 3, "acceptance_by_task" => [1, 2])
    report = Dict{String,Any}("ranking" => [zero, partial, positive], "complete" => true)
    filtered = ZeroScorePropertyFilter.remove_zero_scores(report)
    @test filtered["ranking"] == [partial, positive]
    @test filtered["zero_total_score_properties_removed"] == 1
    @test report["ranking"] == [zero, partial, positive]
    @test filtered["ranking"][1]["acceptance_by_task"] == [0, 2]
    @test filtered["complete"]
end
