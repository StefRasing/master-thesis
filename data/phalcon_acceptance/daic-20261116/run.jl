include(joinpath(dirname(Base.active_project()), "experiments/src/Experiments.jl"))
using .Experiments
using JSON3

root, mode, domain = ARGS
rank = parse(Int, ENV["SLURM_PROCID"])
if mode == "pilot"
    benchmark = (:strings, :bitvectors)[rank + 1]
    task = (["11440431"], ["PRE_100_10"])[rank + 1]
    threshold, run, timeout = 100, "1", 2
    indices = Colon()
    output = joinpath(root, "pilot", string(benchmark), "threshold-100.runs")
else
    benchmark = Symbol(domain)
    count = (strings=124, bitvectors=151)[benchmark]
    width = 8
    batches = cld(count, width)
    setting, batch = divrem(parse(Int, ENV["SLURM_ARRAY_TASK_ID"]) - 1, batches)
    threshold = (5, 10, 25, 50, 100, 99)[setting ÷ 5 + 1]
    run = string(setting % 5 + 1)
    index = batch * width + rank + 1
    index <= count || exit(0)
    task, indices, timeout = nothing, index:index, 1800
    output = joinpath(root, "results", domain, "threshold-$threshold.runs")
end

config = ExperimentConfig(; algorithm=:phalcon, benchmark, task_names=task,
    problem_indices=indices, run, seed=1, repetitions=1, timeout, output,
    iterator_options=(population_size=100,),
    phalcon_options=(agreement_threshold=threshold,
        max_number_of_properties=typemax(Int), max_property_evaluations=10_000))
tasks = Experiments.benchmark_tasks(config, benchmark_adapter(benchmark))
length(tasks) == 1 || error("Expected one problem")
problem = only(tasks).problem
expected = length(Experiments.evaluation_folds(config, problem))
println("Starting $benchmark / $(problem.name) / run $run / threshold $threshold ($expected folds)")
flush(stdout)
run_experiment(config)
println("Finished $benchmark / $(problem.name) / run $run / threshold $threshold")
flush(stdout)

if mode == "pilot"
    records = Experiments.load_results(output)
    @assert length(records) == expected == 5
    @assert all(r -> Experiments.completed_run(output, r["identity"]), records)
    @assert all(records) do r
        phalcon = r["result"]["effective_configuration"]["phalcon"]
        phalcon["agreement_threshold"] == threshold &&
            phalcon["max_number_of_properties"] == typemax(Int)
    end
end
