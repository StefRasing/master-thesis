# Diagnostic full-suite pass: tiny search budgets; never use these for accuracy.
include("src/Experiments.jl")
using .Experiments, JSON3, Dates
root = length(ARGS) >= 1 ? abspath(ARGS[1]) : joinpath(@__DIR__, "../data/preflight", Dates.format(now(), "yyyymmdd-HHMMSS"))
budget = length(ARGS) >= 2 ? parse(Float64, ARGS[2]) : 0.05
mkpath(root)
summary = Any[]
for domain in (:strings, :bitvectors, :arc), algorithm in (:heuristic, :phalcon)
    path = joinpath(root, "$(algorithm)_$(domain).runs")
    config = ExperimentConfig(; algorithm, benchmark=domain, timeout=budget, output=path, run="preflight")
    println("Checking $algorithm / $domain → $path"); flush(stdout)
    try
        adapter = benchmark_adapter(domain)
        tasks = Experiments.benchmark_tasks(config, adapter)
        expected = sum(length(Experiments.evaluation_folds(config, t.problem)) for t in tasks)
        run_experiment(config)
        records = Experiments.load_results(path)
        length(records) == expected || error("expected $expected records, got $(length(records))")
        for record in records
            Experiments.completed_run(path, record["identity"]) || error("resume check failed")
            r = record["result"]
            for key in ("problem_name", "solution", "execution_time", "programs_enumerated", "properties_enumerated", "fold", "folds", "train_test_split", "test_examples", "correct_test_examples", "effective_configuration")
                haskey(r, key) || error("missing metric $key")
            end
        end
        Experiments.export_legacy(path, joinpath(root, "$(algorithm)_$(domain)_metrics.json"))
        push!(summary, Dict("algorithm"=>algorithm, "domain"=>domain, "status"=>"passed", "problems"=>length(tasks), "records"=>length(records)))
    catch err
        showerror(stderr, err, catch_backtrace()); println(stderr)
        push!(summary, Dict("algorithm"=>algorithm, "domain"=>domain, "status"=>"failed", "error"=>sprint(showerror, err)))
    end
    open(joinpath(root, "summary.json"), "w") do io
        JSON3.pretty(io, summary)
    end
    flush(stdout)
end
all(r -> r["status"] == "passed", summary) || exit(1)
