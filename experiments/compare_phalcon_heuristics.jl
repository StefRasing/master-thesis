# julia --project=. experiments/compare_phalcon_heuristics.jl [old_root new_root output_dir]
include("plot_phalcon_ablation.jl")

const ABLATION = dirname(DEFAULT_RESULTS)
const OLD_ROOT = joinpath(ABLATION, "daic-uncapped-20261112-snapshot-20261113")
const NEW_ROOT = joinpath(ABLATION, "daic-all-agreement-uncapped-20261112")
const COMPARISON_OUTPUT = joinpath(NEW_ROOT, "comparison")
const OLD_POPULATION = 25
const NEW_POPULATION = 20

function comparison_metadata(root, population)
    directory = joinpath(root, "strings", "pop-$(population).runs")
    metadata = Dict()
    for path in readdir(joinpath(directory, "results"); join=true)
        endswith(path, ".json") || continue
        row = JSON3.read(read(path, String))
        id = row.identity
        result = row.result
        config = result.effective_configuration
        @assert config.phalcon.max_number_of_properties == typemax(Int) path
        @assert isfile(joinpath(directory, "provenance", row.provenance_sha256 * ".json")) path
        key = (parse(Int, id.configuration.run), String(id.problem), Int(id.fold))
        @assert !haskey(metadata, key) path
        iterator = Dict(k => v for (k, v) in pairs(config.iterator) if k != :population_size)
        metadata[key] = (id.seed, id.repetition, result.train_test_split, config.timeout,
            config.phalcon, iterator, id.configuration.timing_protocol)
    end
    return metadata
end

function comparison_plot(old, new, field, xlabel)
    ax = panel("Strings"; xlabel, ylabel="Folds solved", legend=:outerbottom, legend_column=2,
        ylims=(0, 103), yticks=0:20:100, yformatter=y -> "$(round(Int, y))%")
    labels = ("Old ($OLD_POPULATION)", "New ($NEW_POPULATION)")
    # A fold can solve before inventing any properties.
    zero_allowed = field == :properties
    coordinate(x) = zero_allowed ? x + 1 : x
    lower, upper = extrema(coordinate(getproperty(fold, field)) for fold in [old; new])
    limits = (zero_allowed ? 1.0 : lower / 1.3, upper * 1.12)
    plot!(ax; xscale=:log10, xlims=limits, xformatter=x -> "1e$(round(Int, log10(x)))")
    if zero_allowed
        plot!(ax; xformatter=:auto)
        ticks = filter(x -> x + 1 <= limits[2], [0, 2, 5, 10, 20, 50, 100, 500, 1000])
        plot!(ax; xticks=(ticks .+ 1, string.(ticks)))
    end
    for (i, (rows, color, label, marker)) in enumerate(zip((old, new), COLORS, labels, MARKERS))
        for (criterion, linestyle) in ((:solved, :solid), (:training_solved, :dot))
            costs = sort!([coordinate(getproperty(fold, field)) for fold in rows if getproperty(fold, criterion)])
            accuracy = 100 .* (1:length(costs)) ./ length(rows)
            plot_steps!(ax, [limits[1]; costs; limits[2]],
                [0; accuracy; 100 * length(costs) / length(rows)], color, marker, i, linestyle;
                label=criterion === :solved ? label : false)
        end
    end
    plot!(ax, [NaN], [NaN]; color=:black, linewidth=2, label="Test")
    plot!(ax, [NaN], [NaN]; color=:black, linewidth=2, linestyle=:dot, label="Training")
    return plot(ax; size=(COLUMN_WIDTH, 216))
end

function compare_heuristics(old_root=OLD_ROOT, new_root=NEW_ROOT, output=COMPARISON_OUTPUT)
    old_metadata = comparison_metadata(old_root, OLD_POPULATION)
    new_metadata = comparison_metadata(new_root, NEW_POPULATION)
    @assert old_metadata == new_metadata "The compared runs must have identical fold identities, seeds, and search settings apart from population."
    keys_sorted = sort!(collect(keys(old_metadata)))
    @assert [count(key -> key[1] == run, keys_sorted) for run in 1:5] == fill(449, 5)
    @assert length(keys_sorted) == 2245
    rows(root, pop) = begin
        groups = load_problem_runs(root, "strings", pop)
        [merge(fold, (; properties=count(>(0), fold.agreements)))
            for (run, problem, index) in keys_sorted for fold in (groups[run, problem][index],)]
    end
    old, new = rows(old_root, OLD_POPULATION), rows(new_root, NEW_POPULATION)
    mkpath(output)
    for (field, xlabel, filename) in (
        (:seconds, "Execution time per fold (s)", "01_execution_time"),
        (:programs, "Programs enumerated per fold", "02_program_enumerations"),
        (:properties, "Properties used per fold", "03_properties_used"),
    )
        save_figure(comparison_plot(old, new, field, xlabel), output, filename)
    end
    for (name, split) in (("Test", :solved), ("Training", :training_solved))
        pairs = [(getproperty(a, split), getproperty(b, split)) for (a, b) in zip(old, new)]
        println(name, ": old=", count(first, pairs), " new=", count(last, pairs),
            " old only=", count(==((true, false)), pairs), " new only=", count(==((false, true)), pairs),
            " both=", count(==((true, true)), pairs), " neither=", count(==((false, false)), pairs))
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) in (0, 3) || error("Usage: compare_phalcon_heuristics.jl [old_root new_root output_dir]")
    compare_heuristics(ARGS...)
end
