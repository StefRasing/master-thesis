function main(args=ARGS)
    2 <= length(args) <= 4 || throw(ArgumentError("usage: run.jl ALGORITHM BENCHMARK [RUN [ARC_SHARD]]"))
    algorithm, benchmark = Symbol.(args[1:2])
    run_experiment(ExperimentConfig(; algorithm, benchmark, repetitions=1,
        run=length(args)>=3 ? args[3] : "1", shard=length(args)==4 ? args[4] : nothing))
end
