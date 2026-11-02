include("../experiments/src/Experiments.jl")
using .Experiments

@testset "Shared experiment runner" begin
    strings = benchmark_adapter(:strings)
    bitvectors = benchmark_adapter(:bitvectors)
    arc = benchmark_adapter(:arc)
    @test strings.property_options.max_property_cost == 3
    @test bitvectors.property_options.max_property_cost == 4
    @test arc.candidate_pool_size == 10000
    @test !arc.rule_cost(:(objects(x)))
    @test arc.rule_cost(:(rotate(x)))
    @test_throws ArgumentError benchmark_adapter(:unknown)
    tasks = Experiments.benchmark_tasks(ExperimentConfig(), strings)
    expected_names = [String(s)[9:end] for s in names(strings.benchmark; all=true)
        if startswith(String(s), "problem_") && all(f -> !occursin(f, String(s)), ["short", "long", "repeat", "small"])]
    @test [t.problem for t in tasks] == [getfield(strings.benchmark, Symbol("problem_", n)) for n in expected_names]
    @test any(t -> t.grammar.rules[1] != :ntString, tasks)
    @test length(Experiments.benchmark_tasks(ExperimentConfig(benchmark=:bitvectors), bitvectors)) == 151
    @test length(Experiments.benchmark_tasks(ExperimentConfig(benchmark=:arc, shard="d"), arc)) == 100
    selected = Experiments.benchmark_tasks(ExperimentConfig(task_names=["2171308"]), strings)
    @test length(selected) == 1
    train, test, indices = Experiments.split_problem(first(selected).problem, [1])
    @test indices == collect(2:length(first(selected).problem.spec))
    @test length(test.spec) == 1
    @test_throws ArgumentError Experiments.split_problem(first(selected).problem, Int[])
    # Exercise synthesis, missing-solution evaluation, storage, and resume cheaply.
    mktempdir() do dir
        path = joinpath(dir, "nested", "result.json")
        config = ExperimentConfig(output=path, task_names=["2171308"], phalcon_options=(timeout=0,))
        results = run_experiment(config)
        @test length(results) == 1
        @test results[1]["solved_train_examples"] === false
        @test results[1]["solved_test_examples"] === false
        @test results[1]["programs_enumerated"] == 0
        @test isempty(run_experiment(config))
        @test Experiments.performed_repetitions(path, first(selected).problem.name) == 1
    end
end
