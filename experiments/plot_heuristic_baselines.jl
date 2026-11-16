# julia --project=. experiments/plot_heuristic_baselines.jl [--first-attempt] [baseline_root phalcon_root output_dir]
include("plot_phalcon_ablation.jl")

const BASELINE_ROOT = joinpath(dirname(dirname(DEFAULT_RESULTS)), "heuristic_pop100", "daic-20261114")
const PHALCON_ROOT = joinpath(dirname(DEFAULT_RESULTS), "daic-uncapped-20261112-pop100")
const METHODS = (("heuristic", "Informed heuristic"), ("heuristic_naive", "Naive heuristic"),
    ("phalcon", "Phalcon"))
const FOLDS_PER_RUN = Dict("strings" => 449, "bitvectors" => 755)

function load_baseline_comparison(root, domain, algorithm; first_attempt=false)
    directories = algorithm == "phalcon" ? [joinpath(root, domain, "pop-100.runs")] :
        [joinpath(root, algorithm, domain, "run-$(run).runs") for run in 1:5]
    rows = Dict{Tuple{Int,String,Int},NamedTuple}()
    for directory in directories, path in readdir(joinpath(directory, "results"); join=true)
        endswith(path, ".json") || continue
        record = JSON3.read(read(path, String))
        id, result = record.identity, record.result
        config = id.configuration
        @assert (config.algorithm, config.benchmark, config.iterator_options.population_size) ==
            (algorithm, domain, 100) path
        @assert (config.timeout, config.timing_protocol, id.repetition) == (1800, "warmed_v1", 1) path
        @assert result.solved_test_examples ==
            (result.correct_test_examples == result.test_examples) path
        key = (parse(Int, config.run), String(id.problem), Int(id.fold))
        @assert !haskey(rows, key) path
        effective = result.effective_configuration
        if !isnothing(effective)
            @assert effective.timeout == 1800 && effective.iterator.population_size == 100 path
        end
        split = (Tuple(result.train_test_split[1]), Tuple(id.test_indices))
        # A later attempt's cumulative costs cannot locate a first-attempt event.
        usable = !first_attempt || result.attempts == 1
        rows[key] = (; split, seed=id.seed, supported=!isnothing(effective),
            solved=usable && result.solved_test_examples,
            training_solved=usable && result.solved_train_examples,
            seconds=usable ? Float64(result.execution_time) : missing,
            programs=usable ? Int(result.programs_enumerated) : missing)
    end
    @assert Set(first.(keys(rows))) == Set(1:5) (domain, algorithm)
    @assert all(run -> count(key -> first(key) == run, keys(rows)) == FOLDS_PER_RUN[domain], 1:5)
    return rows
end

function plot_baselines(baseline_root=BASELINE_ROOT, phalcon_root=PHALCON_ROOT,
    output=nothing; first_attempt=false)
    output = something(output, joinpath(baseline_root,
        first_attempt ? "comparison_first_attempt" : "comparison"))
    domains = first_attempt ? (last(DOMAINS),) : DOMAINS
    methods = first_attempt ? (METHODS[1], ("heuristic_naive", "Naive heuristic (attempt 1)"), METHODS[3]) : METHODS
    data = Dict()
    for (domain, _) in domains
        reference = nothing
        for (algorithm, label) in methods
            root = algorithm == "phalcon" ? phalcon_root : baseline_root
            rows = load_baseline_comparison(root, domain, algorithm;
                first_attempt=first_attempt && algorithm == "heuristic_naive")
            splits = Dict(key => (row.split, row.seed) for (key, row) in rows)
            if isnothing(reference)
                reference = splits
            end
            @assert reference == splits "Mismatched folds or seeds for $(domain) / $(algorithm)"
            groups = Dict{Tuple{Int,String},Dict{Int,NamedTuple}}()
            for ((run, problem, fold), row) in rows
                get!(groups, (run, problem), Dict{Int,NamedTuple}())[fold] = row
            end
            data[domain, algorithm] = groups
            println("$(domain) / $(label): $(count(row -> row.solved, values(rows)))/$(length(rows)) solved, ",
                "$(count(row -> !row.supported, values(rows))) unsupported")
        end
    end
    mkpath(output)
    labels = Dict(methods)
    series = first.(methods)
    for (field, xlabel, filename) in (
        (:seconds, "Execution time per fold (s)", "01_execution_time"),
        (:programs, "Programs enumerated per fold", "02_program_enumerations"),
    )
        figure = performance(data, series, field, xlabel; show_bounds=true, domains,
            series_label=method -> labels[method], legend_title="Method / split")
        save_figure(figure, output, filename)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    first_attempt = "--first-attempt" in ARGS
    paths = filter(!=("--first-attempt"), ARGS)
    length(paths) in (0, 3) ||
        error("Usage: plot_heuristic_baselines.jl [--first-attempt] [baseline_root phalcon_root output_dir]")
    plot_baselines(paths...; first_attempt)
end
