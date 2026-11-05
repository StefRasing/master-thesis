# Run each algorithm/domain in a fresh process with --threads=1 --startup-file=no.
# This is a bounded pilot, not a full-budget memory guarantee.
started = time()
include("../src/Experiments.jl")
using .Experiments, JSON3
algorithm, domain = Symbol.(ARGS[1:2])
budget = length(ARGS) >= 3 ? parse(Float64, ARGS[3]) : 10.0
destination = length(ARGS) >= 4 ? ARGS[4] : "resource_probe.json"
config = ExperimentConfig(; algorithm, benchmark=domain, store=false, timeout=budget)
adapter = benchmark_adapter(domain)
tasks = Experiments.benchmark_tasks(config, adapter)
fold_counts = [length(Experiments.evaluation_folds(config, t.problem)) for t in tasks]
# Spread across the selected suite; retain normal folds, preparation and warm-up.
indices = unique([1, cld(length(tasks), 2), length(tasks)])
pilot = ExperimentConfig(; algorithm, benchmark=domain, store=false, timeout=budget,
    problem_indices=indices, seed=42)
loaded = time() - started
measurement = @timed run_experiment(pilot)
report = Dict("algorithm"=>algorithm, "domain"=>domain, "julia"=>string(VERSION),
    "machine"=>Sys.MACHINE, "cpu"=>Sys.CPU_NAME, "threads"=>Threads.nthreads(),
    "timeout_seconds"=>budget, "task_count"=>length(tasks), "fold_count"=>sum(fold_counts),
    "selected_indices"=>indices, "load_seconds"=>loaded,
    "pilot_seconds"=>measurement.time, "gc_seconds"=>measurement.gctime,
    "allocated_bytes"=>measurement.bytes, "process_peak_rss_bytes"=>Sys.maxrss(),
    "trials"=>measurement.value)
open(destination, "w") do io
    JSON3.pretty(io, report)
end
println("Resource report: ", destination)
