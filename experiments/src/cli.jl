const PHALCON_ABLATION_SETTINGS = [
    (population_size=population_size, max_property_cost=max_property_cost)
    for population_size in (10, 20, 50, 100) for max_property_cost in 1:4
]

function ablation_settings()
    sizes = get(ENV, "PHALCON_ABLATION_POPULATIONS", "")
    isempty(sizes) && return PHALCON_ABLATION_SETTINGS
    populations = parse.(Int, split(sizes, ','))
    all(>(0), populations) && allunique(populations) ||
        throw(ArgumentError("PHALCON_ABLATION_POPULATIONS must contain distinct positive sizes"))
    return [(; population_size, max_property_cost) for population_size in populations for max_property_cost in 1:4]
end

function batch_indices(benchmark, index_arg, size_arg)
    index, size = parse.(Int, (index_arg, size_arg))
    index > 0 && size > 0 || throw(ArgumentError("batch index and size must be positive"))
    count = length(benchmark_tasks(ExperimentConfig(; benchmark), benchmark_adapter(benchmark)))
    index <= cld(count, size) || throw(ArgumentError("batch index exceeds suite"))
    first = (index - 1) * size + 1
    return first:(first + min(size - 1, count - first))
end

function phalcon_ablation(args)
    run = "1"
    if length(args) == 8 && args[7] == "--run"
        run = args[8]
        args = args[1:6]
    end
    batch = length(args) == 6 && args[4] == "--batch"
    (2 <= length(args) <= 3 || batch) || throw(ArgumentError(
        "usage: run.jl phalcon-ablation BENCHMARK [SETTING [--batch INDEX SIZE [--run RUN]]]"))
    benchmark = Symbol(args[2])
    settings = ablation_settings()
    if length(args) >= 3
        setting = tryparse(Int, args[3])
        !isnothing(setting) && setting in eachindex(settings) ||
            throw(ArgumentError("SETTING must be 1–$(length(settings))"))
        settings = (settings[setting],)
    end
    problem_indices = batch ? batch_indices(benchmark, args[5], args[6]) : Colon()
    output_root = get(ENV, "PHALCON_ABLATION_OUTPUT_ROOT",
        joinpath(@__DIR__, "..", "..", "data", "phalcon_ablation"))
    for (; population_size, max_property_cost) in settings
        output = joinpath(output_root, string(benchmark),
            "pop-$(population_size)_cost-$(max_property_cost).runs")
        # Each independent run uses paired seeds across settings.
        run_experiment(ExperimentConfig(; algorithm=:phalcon, benchmark, repetitions=1, run,
            output, problem_indices, iterator_options=(; population_size),
            phalcon_options=(; max_property_cost)))
    end
end

function main(args=ARGS)
    !isempty(args) && args[1] == "phalcon-ablation" && return phalcon_ablation(args)
    batch = length(args) == 6 && args[4] == "--batch"
    (2 <= length(args) <= 4 || batch) || throw(ArgumentError("usage: run.jl ALGORITHM BENCHMARK [RUN [ARC_SHARD] | RUN --batch INDEX SIZE]"))
    algorithm, benchmark = Symbol.(args[1:2])
    indices = batch ? batch_indices(benchmark, args[5], args[6]) : Colon()
    run_experiment(ExperimentConfig(; algorithm, benchmark, repetitions=1,
        run=length(args)>=3 ? args[3] : "1", shard=length(args)==4 ? args[4] : nothing,
        problem_indices=indices))
end
