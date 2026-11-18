include(joinpath(dirname(Base.active_project()), "experiments/src/Experiments.jl"))
using .Experiments

root, domain = ARGS
benchmark = Symbol(domain)
caps = (5, 10, 20, 40)
ordinal = parse(Int, ENV["SLURM_ARRAY_TASK_ID"]) - 1
index, setting = divrem(ordinal, length(caps))
index += 1
cap = caps[setting + 1]
output = joinpath(root, "results", domain, "properties-$(cap).runs")
config = ExperimentConfig(; algorithm=:phalcon_domain, benchmark, run="1",
    ranking_path=joinpath(root, "rankings"), output, problem_indices=index:index,
    phalcon_options=(max_number_of_properties=cap,))
adapter = benchmark_adapter(benchmark)
tasks = Experiments.benchmark_tasks(config, adapter)
task = only(tasks)
folds = Experiments.evaluation_folds(config, task.problem)
println("Starting $domain / $(task.problem.name) / $cap properties / $(length(folds)) folds")
flush(stdout)
records = run_experiment(config)
for record in records
    fold = record["identity"]["fold"]
    ranking_file = Experiments.domain_ranking_file(config.ranking_path, benchmark, fold)
    expected_hash = bytes2hex(Experiments.sha256(read(ranking_file)))
    @assert record["identity"]["ranking_sha256"] == expected_hash
    @assert record["identity"]["test_indices"] == folds[fold]
    Experiments.display_result(stdout, record["result"])
end
println("Finished $domain / $(task.problem.name) / $cap properties")
flush(stdout)
