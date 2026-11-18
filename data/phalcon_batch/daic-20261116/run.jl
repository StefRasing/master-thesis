include(joinpath(dirname(Base.active_project()), "experiments/src/Experiments.jl"))
using .Experiments

root, mode, domain = ARGS
caps = (5, 10, 20, 40)
rank = parse(Int, ENV["SLURM_PROCID"])
if mode == "pilot"
    benchmark = (:strings, :bitvectors)[rank ÷ length(caps) + 1]
    cap, run, index, timeout = caps[mod1(rank + 1, length(caps))], "1", 1, 60
else
    benchmark = Symbol(domain)
    width = 4
    count = (strings=124, bitvectors=151)[benchmark]
    batches = cld(count, width)
    ordinal, batch = divrem(parse(Int, ENV["SLURM_ARRAY_TASK_ID"]) - 1, batches)
    index = batch * width + rank ÷ length(caps) + 1
    index > count && exit(0)
    cap, run, timeout = caps[mod1(rank + 1, length(caps))], string(ordinal + 1), 1800
end
output = joinpath(root, mode == "pilot" ? "pilot" : "results",
    string(benchmark), "properties-$(cap).runs")
config = ExperimentConfig(; algorithm=:phalcon_batch, benchmark, run, timeout, output,
    problem_indices=index:index, iterator_options=(population_size=100,),
    phalcon_options=(max_number_of_properties=cap,))

adapter = benchmark_adapter(benchmark)
suite = Experiments.benchmark_tasks(ExperimentConfig(; algorithm=:phalcon_batch, benchmark), adapter)
count, folds = (strings=(124, 449), bitvectors=(151, 755))[benchmark]
@assert length(suite) == count
@assert sum(length(Experiments.evaluation_folds(config, task.problem)) for task in suite) == folds
problem = suite[index].problem
expected = length(Experiments.evaluation_folds(config, problem))
println("Starting $benchmark / $(problem.name) / run $run / cap $cap ($expected folds)")
flush(stdout)
run_experiment(config)

if mode == "pilot"
    records = Experiments.load_results(output)
    @assert length(records) == expected == 5
    for record in records
        @assert Experiments.completed_run(output, record["identity"])
        result = record["result"]
        settings = result["effective_configuration"]
        @assert settings["iterator"]["population_size"] == 100
        @assert settings["phalcon"]["max_number_of_properties"] == cap
        @assert result["property_sample_target"] == 100 * cap
    end
    provenance = Experiments.run_provenance()
    @assert !isnothing(provenance["code"]["revision"])
    @assert !isnothing(provenance["environment"]["interpreter"]["revision"])
end
println("Finished $benchmark / $(problem.name) / run $run / cap $cap")
flush(stdout)
