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
    @test ExperimentConfig().timeout == 1800
    # A zero shared budget cancels both algorithms before interpreter creation.
    supported = first(t for t in tasks if t.grammar.rules[1] == :ntString)
    for algorithm in (:heuristic, :phalcon)
        interpreter = Ref{Any}(nothing)
        result = Experiments.run_trial(ExperimentConfig(; algorithm, timeout=0), strings,
            supported.problem, supported.grammar; interpreter_ref=interpreter)
        @test !result["solved_train_examples"] && !result["solved_test_examples"]
        @test result["programs_enumerated"] == 0
        @test isnothing(interpreter[])
        @test result["effective_configuration"]["timeout"] == 0
        @test result["effective_configuration"]["iterator"]["max_generations_without_improvement"] == 10
    end
    unsupported = first(t for t in tasks if t.grammar.rules[1] != :ntString)
    result = Experiments.run_trial(ExperimentConfig(algorithm=:heuristic), strings,
        unsupported.problem, unsupported.grammar)
    @test !result["solved_train_examples"] && !result["solved_test_examples"]
    @test result["execution_time"] == 0 && result["programs_enumerated"] == 0
    @test isnothing(result["effective_configuration"])
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
        @test results[1]["schema_version"] == 3
        @test !haskey(results[1], "provenance")
        @test isfile(joinpath(path, "provenance", results[1]["provenance_sha256"] * ".json"))
        @test isdir(joinpath(path, "results"))
        @test results[1]["result"]["solved_train_examples"] === false
        @test results[1]["result"]["solved_test_examples"] === false
        @test results[1]["result"]["programs_enumerated"] == 0
        @test isempty(run_experiment(config))
        @test length(Experiments.load_results(path)) == 1
        changed = ExperimentConfig(output=path, task_names=["2171308"], seed=2, phalcon_options=(timeout=0,))
        @test length(run_experiment(changed)) == 1
        extended = ExperimentConfig(output=path, task_names=["2171308"], repetitions=2, phalcon_options=(timeout=0,))
        @test length(run_experiment(extended)) == 1
        @test length(Experiments.load_results(path)) == 3
        @test length(readdir(joinpath(path, "provenance"))) == 1
    end
end

@testset "Atomic run records and identities" begin
    @test Experiments.fingerprint(Dict("b"=>2, "a"=>1)) == Experiments.fingerprint(Dict("a"=>1, "b"=>2))
    mktempdir() do dir
        identity = Dict("problem"=>"p", "configuration"=>Dict("budget"=>1), "seed"=>"42", "repetition"=>1)
        record = Dict("schema_version"=>2, "identity"=>identity,
            "run_id"=>Experiments.fingerprint(identity), "result"=>Dict("solution"=>"first"))
        @test startswith(Experiments.result_filename(identity), "p__rep-1__seed-42__")
        @test !occursin("/", Experiments.result_filename(merge(identity, Dict("problem"=>"../a/b"))))
        @test !Experiments.completed_run(dir, identity)
        # An interrupted write is invisible to the loader and resume logic.
        write(joinpath(dir, "jl_interrupted"), "{broken")
        Experiments.append_result(dir, record)
        duplicate = deepcopy(record)
        duplicate["result"]["solution"] = "second"
        @sync for _ in 1:8
            Threads.@spawn Experiments.append_result(dir, duplicate)
        end
        @test Experiments.completed_run(dir, identity)
        @test length(Experiments.load_results(dir)) == 1
        # Existing hash-only records must still resume after the naming change.
        readable = joinpath(dir, Experiments.result_filename(identity))
        legacy = joinpath(dir, record["run_id"] * ".json")
        mv(readable, legacy)
        @test Experiments.completed_run(dir, identity)
        mv(legacy, readable)
        @test only(Experiments.load_results(dir))["result"]["solution"] == "first"
        for (key, value) in (("seed", "43"), ("repetition", 2), ("configuration", Dict("budget"=>2)))
            changed = merge(identity, Dict(key=>value))
            @test !Experiments.completed_run(dir, changed)
        end
        export_path = joinpath(dirname(dir), basename(dir) * ".json")
        try
            Experiments.export_legacy(dir, export_path)
            @test only(Experiments.load_results(export_path))["solution"] == "first"
        finally
            rm(export_path; force=true)
        end
    end
    # Genetic operations consume only the explicitly supplied RNG.
    g = @csgrammar begin
        Start = 1
        Start = 2
        Start = Start + Start
    end
    make_iter(seed) = GeneticIterator(g, :Start; rng=Experiments.Random.Xoshiro(seed),
        problem=(spec=[IOExample(Dict{Symbol,Any}(), 99)],), cost=_ -> 1,
        rule_costs=[1,1,1], benchmark=TypedStorageDSL)
    a, b = make_iter(42), make_iter(42)
    initialize!(a); initialize!(b)
    pa = RuleNodeWithRuleCounts(a, RuleNode(3, [RuleNode(1), RuleNode(2)]))
    pb = RuleNodeWithRuleCounts(b, RuleNode(3, [RuleNode(1), RuleNode(2)]))
    for _ in 1:20
        _, path_a = Phalcon.random_subtree(a, pa, fill(true, 3))
        Experiments.Random.rand(100) # unrelated default RNG activity
        _, path_b = Phalcon.random_subtree(b, pb, fill(true, 3))
        @test path_a == path_b
    end
end

@testset "Playgrounds can be included repeatedly in a REPL" begin
    # Execute the real clients with a lightweight runner so this test does not
    # launch the full benchmark searches. Conflicting exports reproduce the REPL
    # state left by an earlier module include.
    sandbox = Module(:PlaygroundREPL)
    Base.include_string(sandbox, """
        module OldClient
            export run_experiment, ExperimentConfig
            run_experiment() = error("stale runner")
            ExperimentConfig() = error("stale config")
        end
        module OtherClient
            export run_experiment, ExperimentConfig
            run_experiment() = error("ambiguous runner")
            ExperimentConfig() = error("ambiguous config")
        end
        using .OldClient, .OtherClient
        module Experiments
            const calls = Any[]
            ExperimentConfig(; kwargs...) = (; kwargs...)
            run_experiment(config) = push!(calls, config)
        end
    """)
    for file in ("heuristic_strings.jl", "phalcon_bitvectors.jl", "phalcon_strings.jl")
        path = joinpath(@__DIR__, "../experiments/playgrounds", file)
        # Activation is already handled by the test entry point; keep this test
        # free of Pkg depot writes, while executing all client module/runner code.
        client = replace(read(path, String), "using Pkg\nPkg.activate(joinpath(@__DIR__, \"..\", \"..\"))\n" => "")
        Base.include_string(sandbox, client, path)
        Base.include_string(sandbox, client, path)
    end
    @test length(sandbox.Experiments.calls) == 6
    @test getproperty.(sandbox.Experiments.calls, :benchmark) == [:strings, :strings, :bitvectors, :bitvectors, :strings, :strings]
end

@testset "Playground output contains outcomes only" begin
    io = IOBuffer()
    results = run_experiment(ExperimentConfig(store=false,
        task_names=["2171308"], repetitions=2, phalcon_options=(timeout=0,)); io)
    output = String(take!(io))
    @test length(results) == 2
    @test occursin("repetition 1/2", output)
    @test occursin("repetition 2/2", output)
    @test occursin("Training: unsolved  |  Test: unsolved", output)
    @test occursin("Programs evaluated: 0", output)
    @test occursin("Solution: none", output)
    @test occursin("Completed 2 trials", output)
    @test all(r -> !haskey(r, "provenance") && !haskey(r, "effective_configuration"), results)
    @test !occursin("manifest_toml", output)
    @test !occursin("rule_costs", output)
end

@testset "Compact embedded provenance safely" begin
    mktempdir() do path
        provenance = Dict("code"=>Dict("sources"=>Dict("a.jl"=>"old source")))
        hash = Experiments.fingerprint(provenance)
        identity = Dict("problem"=>"p", "seed"=>"1", "repetition"=>1, "provenance_sha256"=>hash)
        record = Dict("schema_version"=>2, "identity"=>identity, "run_id"=>Experiments.fingerprint(identity),
            "provenance"=>provenance, "result"=>Dict("solution"=>"original"))
        Experiments.append_result(path, record)
        @test Experiments.compact_results!(path) == 1
        @test Experiments.compact_results!(path) == 0
        compact = only(Experiments.load_results(path))
        @test !haskey(compact, "provenance")
        @test compact["result"]["solution"] == "original"
        @test Experiments.completed_run(path, identity)
        @test length(readdir(joinpath(path, "provenance"))) == 1
    end
end

@testset "Search result JSON round trip" begin
    iter = contract_iterator()
    options = (property_types=[:Start], max_property_cost=1, rule_cost_func=_ -> 1)
    # Use actual search results, including an absent solution and empty traces.
    _, result = phalcon(; iterator=iter, options..., timeout=0)
    parsed = Experiments.JSON3.read(Experiments.JSON3.write(result))
    @test Set(string.(keys(parsed))) == Set(keys(result))
    @test parsed["solution"] === nothing
    @test parsed["solved_train_examples"] === false
    @test parsed["problem_name"] == "contracts"
    @test parsed["programs_enumerated"] == result["programs_enumerated"]
    @test parsed["execution_time"] >= 0
    for key in ("heuristic", "population_costs", "program_synthesis_durations", "property_invention_durations")
        @test isempty(parsed[key])
    end
    mktempdir() do dir
        identity = Dict("problem"=>"contracts", "seed"=>"42", "repetition"=>1)
        record = Dict("schema_version"=>2, "identity"=>identity, "result"=>result)
        Experiments.append_result(dir, record)
        @test Experiments.completed_run(dir, identity)
        @test only(Experiments.load_results(dir))["result"] == parsed
    end
end

@testset "Experiment interpreter ownership" begin
    adapter = benchmark_adapter(:strings)
    task = only(Experiments.benchmark_tasks(ExperimentConfig(task_names=["2171308"]), adapter))
    config = ExperimentConfig(store=false, phalcon_options=(timeout=0.1,))
    shared = Ref{Any}(nothing)
    Experiments.run_trial(config, adapter, task.problem, task.grammar; interpreter_ref=shared)
    @test !isnothing(shared[])
    first_interpreter = shared[]
    Experiments.run_trial(config, adapter, task.problem, task.grammar; interpreter_ref=shared)
    @test shared[] === first_interpreter
    independent = Ref{Any}(nothing)
    Experiments.run_trial(config, adapter, task.problem, task.grammar; interpreter_ref=independent)
    @test independent[] !== first_interpreter
    expired = Ref{Any}(nothing)
    Experiments.run_trial(ExperimentConfig(store=false, phalcon_options=(timeout=0,)),
        adapter, task.problem, task.grammar; interpreter_ref=expired)
    @test isnothing(expired[])
    @test ExperimentConfig().reuse_interpreter
    @test !ExperimentConfig(reuse_interpreter=false).reuse_interpreter
end

@testset "ARC higher-order rule evaluators" begin
    dsl = benchmark_adapter(:arc).benchmark
    grammar = dsl.grammar_hodel
    output = HerbInterpret.make_output_interpreter(grammar; target_module=dsl, cache_module=dsl)
    predicate = findfirst(eachindex(grammar.rules)) do i
        grammar.types[i] == :IntToBoolFunc && grammar.rules[i] isa Expr && grammar.rules[i].head == :->
    end
    negation = findfirst(eachindex(grammar.rules)) do i
        grammar.types[i] == :IntToBoolFunc && grammar.rules[i] == :(negate(IntToBoolFunc))
    end
    @test !isnothing(predicate) && !isnothing(negation)
    inputs = [Dict{Symbol,Any}() for _ in 1:3]
    for thresholds in ([1, 3, 5], [5, 1, 3])
        fs = output(predicate, [thresholds], inputs)
        @test [f(4) for f in fs] == [dsl.greater(4, n) for n in thresholds]
        ns = output(negation, [fs], inputs)
        @test [f(4) for f in ns] == [!dsl.greater(4, n) for n in thresholds]
    end
    fs = output(predicate, [[1, nothing, 5]], inputs)
    ns = output(negation, [fs], inputs)
    @test ns[1](4) == false
    @test isnothing(ns[2])
    @test ns[3](4) == true
end
