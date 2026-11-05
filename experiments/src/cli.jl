function main(args=ARGS)
    batch = length(args) == 6 && args[4] == "--batch"
    (2 <= length(args) <= 4 || batch) || throw(ArgumentError("usage: run.jl ALGORITHM BENCHMARK [RUN [ARC_SHARD] | RUN --batch INDEX SIZE]"))
    algorithm, benchmark = Symbol.(args[1:2])
    indices = Colon()
    if batch
        index, size = parse.(Int, args[5:6])
        index > 0 && size > 0 || throw(ArgumentError("batch index and size must be positive"))
        count = length(benchmark_tasks(ExperimentConfig(; benchmark), benchmark_adapter(benchmark)))
        first = (index - 1) * size + 1
        first <= count || throw(ArgumentError("batch index exceeds suite"))
        indices = first:min(index * size, count)
    end
    run_experiment(ExperimentConfig(; algorithm, benchmark, repetitions=1,
        run=length(args)>=3 ? args[3] : "1", shard=length(args)==4 ? args[4] : nothing,
        problem_indices=indices))
end
