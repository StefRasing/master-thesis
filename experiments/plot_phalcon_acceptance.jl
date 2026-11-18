# julia --project=. experiments/plot_phalcon_acceptance.jl [snapshot_dir] [baseline_dir]
include("plot_phalcon_ablation.jl")

const ACCEPTANCE_ROOT = normpath(joinpath(@__DIR__, "..", "data", "phalcon_acceptance", "daic-20261116"))
const ACCEPTANCE_BASELINE = joinpath(dirname(DEFAULT_RESULTS), "daic-uncapped-20261112-pop100")
const THRESHOLDS = (1, 5, 10, 25, 50, 99)
const ACCEPTANCE_COLORS = (COLORS[1:5]..., "#A05278")
const ACCEPTANCE_MARKERS = (MARKERS[1:5]..., :hexagon)

function acceptance_records(directory, threshold; domain="strings")
    records = Dict{Tuple{Int,String,Int},NamedTuple}()
    for path in readdir(directory; join=true)
        endswith(path, ".json") || continue
        row = JSON3.read(read(path, String))
        id, result = row.identity, row.result
        cfg = id.configuration
        options = result.effective_configuration.phalcon
        @assert cfg.benchmark == domain && cfg.algorithm == "phalcon" path
        @assert cfg.iterator_options.population_size == 100 && cfg.timeout == 1800 path
        @assert get(options, :agreement_threshold, 1) == threshold path
        @assert options.max_number_of_properties == typemax(Int) path
        @assert options.max_property_evaluations == 10_000 path
        @assert result.solved_test_examples == (result.test_examples == result.correct_test_examples) path
        key = (parse(Int, cfg.run), String(id.problem), Int(id.fold))
        @assert !haskey(records, key) path
        records[key] = (; seed=String(id.seed), split=Tuple(id.test_indices),
            seconds=result.execution_time, programs=result.programs_enumerated,
            train=result.solved_train_examples, test=result.solved_test_examples,
            properties=count(!=("failed"), result.heuristic),
            agreements=Int[prop[2] for prop in result.heuristic if prop != "failed"],
            search=Float64.(result.program_synthesis_durations),
            invention=Float64.(result.property_invention_durations))
    end
    return records
end

function repetition_weights(common)
    run_counts = Dict{Int,Int}()
    for (run, _, _) in common
        run_counts[run] = get(run_counts, run, 0) + 1
    end
    return Dict(run => 100 / (length(run_counts) * count) for (run, count) in run_counts)
end

function acceptance_performance(datasets, field, xlabel)
    all_costs = [getproperty(rows[key], field) for (records, common) in datasets
        for rows in records for key in common]
    offset = field === :properties ? 1 : 0
    lower = offset == 1 ? 1.0 : minimum(all_costs) / 1.15
    upper = (maximum(all_costs) + offset) * 1.08
    @assert lower > 0
    panels = map(collect(enumerate(datasets))) do (domain_index, (records, common))
        weights = repetition_weights(common)
        title = domain_index == 1 ? "Strings" : "Bitvectors"
        ax = panel(title; xlabel, ylabel=domain_index == 1 ? "Folds solved" : "",
            xscale=:log10, xlims=(lower, upper), ylims=(0, 103), yticks=0:20:100,
            yformatter=y -> "$(round(Int, y))%", legend=domain_index == 1 ? :bottomright : false,
            legend_title="Threshold / split", legend_column=2, legendfontsize=5, legendtitlefontsize=5,
            left_margin=5mm, bottom_margin=4mm)
        if offset == 1
            ticks = filter(<=(maximum(all_costs)), [0, 1, 3, 10, 30, 100, 300, 1000, 3000])
            plot!(ax; xticks=(ticks .+ 1, string.(ticks)))
        end
        for (i, threshold) in enumerate(THRESHOLDS)
            rows = records[i]
            for (split, style) in ((:test, :solid), (:train, :dash))
                events = sort!([(getproperty(rows[key], field) + offset, weights[key[1]])
                    for key in common if getproperty(rows[key], split)])
                x = [lower; first.(events); upper]
                y = [0; cumsum(last.(events)); sum(last, events; init=0.0)]
                plot_steps!(ax, x, y, ACCEPTANCE_COLORS[i], ACCEPTANCE_MARKERS[i], i, style;
                    label=split === :test ? string(threshold) : false)
            end
        end
        if domain_index == 1
            plot!(ax, [NaN], [NaN]; color=:black, label="Test")
            plot!(ax, [NaN], [NaN]; color=:black, linestyle=:dash, label="Training")
        end
        ax
    end
    return plot(panels...; layout=(1, 2), size=(PAPER_WIDTH, 260))
end

function property_count_plots(records, common; title="Strings")
    weights = repetition_weights(common)
    max_properties = maximum(rows[key].properties for rows in records for key in common if rows[key].train)
    last_exact_bin = 20
    histogram = panel(title;
        xlabel="Properties used per fold", ylabel="Solved fold-runs",
        xticks=([0, 5, 10, 15, 20, 21], ["0", "5", "10", "15", "20", "21+"]),
        xlims=(-0.6, 22), legend=:topright, legend_title="Threshold",
        size=(PAPER_WIDTH, 235), left_margin=5mm, bottom_margin=4mm)
    means = Tuple{Float64,String}[]
    for (i, threshold) in enumerate(THRESHOLDS)
        rows = records[i]
        counts = [rows[key].properties for key in common if rows[key].test]
        average = isempty(counts) ? nothing : sum(counts) / length(counts)
        label = isnothing(average) ? string(threshold) : "$threshold (mean $(round(average; digits=2)))"
        isnothing(average) || push!(means, (average, ACCEPTANCE_COLORS[i]))
        stephist!(histogram, min.(counts, last_exact_bin + 1); bins=-0.5:1:(last_exact_bin + 1.5),
            color=ACCEPTANCE_COLORS[i], linestyle=LINE_STYLES[mod1(i, length(LINE_STYLES))],
            linewidth=1.5, label)
    end
    for (average, color) in means
        vline!(histogram, [min(average, last_exact_bin + 1)]; color, linestyle=:dash,
            linewidth=1.2, label=false)
    end

    ticks = [0, 1, 3, 10, 30, 100, 300]
    ticks = filter(<=(max_properties), ticks)
    panels = map(((:test, "Held-out examples"), (:train, "Training examples"))) do (split, title)
        ax = panel(title; xlabel="Properties used per fold", ylabel=split === :test ? "Folds solved" : "",
            xscale=:log10, xlims=(1, max_properties + 2), xticks=(ticks .+ 1, string.(ticks)),
            ylims=(0, 103), yticks=0:20:100, yformatter=y -> "$(round(Int, y))%",
            legend=split === :train ? :bottomright : false, legend_title="Threshold",
            left_margin=5mm, bottom_margin=4mm)
        for (i, threshold) in enumerate(THRESHOLDS)
            rows = records[i]
            exact_accuracy = zeros(max_properties + 1)
            for key in common
                row = rows[key]
                getproperty(row, split) || continue
                exact_accuracy[row.properties + 1] += weights[key[1]]
            end
            cumulative = cumsum(exact_accuracy)
            @assert isapprox(last(cumulative), sum(weights[key[1]] for key in common
                if getproperty(rows[key], split); init=0.0))
            # Offset the log-scale coordinates by one to include zero properties.
            plot_steps!(ax, 1:(max_properties + 2), [cumulative; last(cumulative)],
                ACCEPTANCE_COLORS[i], ACCEPTANCE_MARKERS[i], i, :solid; label=string(threshold))
        end
        ax
    end
    return histogram, plot(panels...; layout=(1, 2), size=(PAPER_WIDTH, 235))
end

function acceptance_iteration_timing(records, common)
    phases = ((:search, "Program search"), (:invention, "Property invention"))
    ranges = (1:1, 2:2, 3:5, 6:10, 11:20, 21:30, 31:40, 41:50)
    labels = ["1", "2", "3–5", "6–10", "11–20", "21–30", "31–40", "41–50"]
    panels = map(phases) do (phase, title)
        ax = panel(title; xlabel="Phalcon iteration range", ylabel="Mean time (s)",
            xticks=(eachindex(ranges), labels), xrotation=35,
            legend=phase === :search ? :topleft : false, legend_title="Threshold",
            left_margin=5mm, bottom_margin=5mm)
        for (i, threshold) in enumerate(THRESHOLDS)
            durations = [getproperty(records[i][key], phase) for key in common]
            means = map(ranges) do iterations
                total = 0.0
                count = 0
                for times in durations, iteration in intersect(iterations, eachindex(times))
                    total += times[iteration]
                    count += 1
                end
                count == 0 ? NaN : total / count
            end
            plot!(ax, eachindex(ranges), collect(means); color=ACCEPTANCE_COLORS[i], marker=ACCEPTANCE_MARKERS[i],
                markersize=2, linewidth=1.2, label=string(threshold))
        end
        ax
    end
    return plot(panels...; layout=(1, 2), link=:x, size=(PAPER_WIDTH, 235))
end

function property_agreement_counts(records, common)
    maxima = Int[]
    panels = map(collect(enumerate(THRESHOLDS))) do (i, threshold)
        counts = zeros(Int, 101)
        above_range = 0
        for key in common, agreement in records[i][key].agreements
            @assert agreement >= 0
            if agreement <= 100
                counts[agreement + 1] += 1
            else
                above_range += 1
            end
        end
        @assert sum(counts) + above_range == sum(records[i][key].properties for key in common)
        println("Threshold $threshold: $(sum(counts)) properties plotted, $above_range above agreement 100")
        observed = findall(>(0), counts)
        push!(maxima, maximum(counts))
        count_ticks = [1, 10, 100, 1000, 10000]
        ax = panel("Threshold $threshold"; xlims=(-2, 102), xticks=0:20:100,
            yscale=:log10,
            yticks=(count_ticks, ["1", "10", "100", "1k", "10k"]),
            xlabel=i > 4 ? "Agreement" : "", ylabel=isodd(i) ? "Property count" : "",
            legend=false, left_margin=5mm, bottom_margin=4mm)
        scatter!(ax, observed .- 1, counts[observed]; color=ACCEPTANCE_COLORS[i],
            markersize=1.5, markerstrokewidth=0)
        ax
    end
    return plot(panels...; layout=(3, 2), ylims=(0.8, max(12_000, 1.25 * maximum(maxima))),
        size=(PAPER_WIDTH, 515))
end

function load_acceptance_domain(results_root, baseline, domain, folds_per_run)
    records = map(THRESHOLDS) do threshold
        directory = threshold == 1 ? joinpath(baseline, domain, "pop-100.runs", "results") :
            joinpath(results_root, domain, "threshold-$threshold.runs", "results")
        acceptance_records(directory, threshold; domain)
    end
    base = first(records)
    common = sort!(collect(intersect((Set(keys(rows)) for rows in records)...)))
    isempty(common) && error("No matched fold-runs across thresholds")
    @assert length(base) == 5 * folds_per_run "Unexpected fold-run count"
    @assert all(Set(keys(rows)) == Set(keys(base)) for rows in records) "Incomplete threshold results"
    @assert all(count(key -> key[1] == run, common) == folds_per_run for run in 1:5)

    for rows in records, (key, row) in rows
        @assert (base[key].seed, base[key].split) == (row.seed, row.split) key
    end
    return records, common
end

function plot_acceptance(root=ACCEPTANCE_ROOT, baseline=ACCEPTANCE_BASELINE)
    results_root = isdir(joinpath(root, "results", "strings")) ? joinpath(root, "results") : root
    datasets = (
        load_acceptance_domain(results_root, baseline, "strings", 449),
        load_acceptance_domain(results_root, baseline, "bitvectors", 755),
    )
    records, common = first(datasets)
    base = first(records)
    output = joinpath(root, "plots")
    mkpath(output)
    open(joinpath(output, "coverage.tsv"), "w") do io
        println(io, "threshold\tsaved\texpected\tmatched\tmatched_test_solved\tmatched_train_solved")
        for (threshold, rows) in zip(THRESHOLDS, records)
            values = (threshold, length(rows), length(base), length(common),
                count(key -> rows[key].test, common), count(key -> rows[key].train, common))
            println(io, join(values, '\t'))
        end
    end
    save_figure(acceptance_performance(datasets, :seconds, "Execution time per fold (s)"),
        output, "01_execution_time")
    save_figure(acceptance_performance(datasets, :programs, "Programs enumerated per fold"),
        output, "02_program_enumerations")
    histograms = map(zip(datasets, ("Strings", "Bitvectors"))) do ((domain_records, domain_common), title)
        histogram, _ = property_count_plots(domain_records, domain_common; title)
        histogram
    end
    histogram_figure = plot(histograms...; layout=(2, 1), link=:x, size=(PAPER_WIDTH, 470))
    save_figure(histogram_figure, output, "03_properties_histogram")
    save_figure(acceptance_performance(datasets, :properties, "Properties used per fold"),
        output, "04_properties_vs_accuracy")
    save_figure(acceptance_iteration_timing(records, common), output, "05_iteration_timing")
    save_figure(property_agreement_counts(records, common), output, "06_property_agreement")
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) <= 2 || error("Usage: plot_phalcon_acceptance.jl [snapshot_dir] [baseline_dir]")
    plot_acceptance(ARGS...)
end
