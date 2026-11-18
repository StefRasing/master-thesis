const PHALCON_ABLATION_POPULATIONS = (10, 20, 40, 80)

function ablation_settings()
    sizes = get(ENV, "PHALCON_ABLATION_POPULATIONS", "")
    isempty(sizes) && return PHALCON_ABLATION_POPULATIONS
    populations = parse.(Int, split(sizes, ','))
    all(>(0), populations) && allunique(populations) ||
        throw(ArgumentError("PHALCON_ABLATION_POPULATIONS must contain distinct positive sizes"))
    return populations
end

function batch_indices(benchmark, index_arg, size_arg; algorithm=:phalcon)
    index, size = parse.(Int, (index_arg, size_arg))
    index > 0 && size > 0 || throw(ArgumentError("batch index and size must be positive"))
    count = length(benchmark_tasks(ExperimentConfig(; benchmark, algorithm), benchmark_adapter(benchmark)))
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
    for population_size in settings
        output = joinpath(output_root, string(benchmark),
            "pop-$(population_size).runs")
        # Each independent run uses paired seeds across settings.
        run_experiment(ExperimentConfig(; algorithm=:phalcon, benchmark, repetitions=1, run,
            output, problem_indices, iterator_options=(; population_size),
            phalcon_options=(max_property_evaluations=Phalcon.DEFAULT_MAX_PROPERTY_EVALUATIONS,)))
    end
end

function domain_rank_cli(args)
    3 <= length(args) <= 4 || throw(ArgumentError(
        "usage: run.jl phalcon-domain-rank BENCHMARK RANKING_DIR [FOLD]"))
    benchmark = Symbol(args[2])
    config = ExperimentConfig(; algorithm=:phalcon_domain, benchmark, ranking_path=args[3],
        timeout=benchmark == :arc ? 14_400 : 1800)
    return run_domain_ranking(config; fold=length(args) == 4 ? parse(Int, args[4]) : nothing)
end

function domain_search_cli(args)
    batch = length(args) == 8 && args[6] == "--batch"
    (4 <= length(args) <= 5 || batch) || throw(ArgumentError(
        "usage: run.jl phalcon-domain-search BENCHMARK RANKING_DIR N [RUN [--batch INDEX SIZE]]"))
    benchmark = Symbol(args[2])
    ranking_path = abspath(args[3])
    max_number_of_properties = parse(Int, args[4])
    max_number_of_properties >= 0 || throw(ArgumentError("N must be nonnegative"))
    run = length(args) >= 5 ? args[5] : "1"
    algorithm = :phalcon_domain
    problem_indices = batch ? batch_indices(benchmark, args[7], args[8]; algorithm) : Colon()
    return run_experiment(ExperimentConfig(; algorithm, benchmark, ranking_path,
        run, problem_indices, phalcon_options=(; max_number_of_properties)))
end

function main(args=ARGS)
    !isempty(args) && args[1] == "phalcon-domain-rank" && return domain_rank_cli(args)
    !isempty(args) && args[1] == "phalcon-domain-search" && return domain_search_cli(args)
    !isempty(args) && args[1] == "phalcon-ablation" && return phalcon_ablation(args)
    batch = length(args) == 6 && args[4] == "--batch"
    (2 <= length(args) <= 4 || batch) || throw(ArgumentError("usage: run.jl ALGORITHM BENCHMARK [RUN [ARC_SHARD] | RUN --batch INDEX SIZE]"))
    algorithm, benchmark = Symbol.(args[1:2])
    algorithm == :phalcon_domain && throw(ArgumentError("use phalcon-domain-rank then phalcon-domain-search"))
    indices = batch ? batch_indices(benchmark, args[5], args[6]; algorithm) : Colon()
    run_experiment(ExperimentConfig(; algorithm, benchmark, repetitions=1,
        run=length(args)>=3 ? args[3] : "1", shard=length(args)==4 ? args[4] : nothing,
        problem_indices=indices))
end
