# julia --project=. experiments/plot_phalcon_acceptance.jl [snapshot_dir] [baseline_dir]
include("plot_phalcon_ablation.jl")

const ACCEPTANCE_ROOT = normpath(joinpath(@__DIR__, "..", "data", "phalcon_acceptance", "daic-20261116"))
const ACCEPTANCE_BASELINE = joinpath(dirname(DEFAULT_RESULTS), "daic-uncapped-20261112-pop100")
const THRESHOLDS = (1, 5, 10, 25, 50, 100)

function acceptance_records(directory, threshold)
    records = Dict{Tuple{Int,String,Int},NamedTuple}()
    for path in readdir(directory; join=true)
        endswith(path, ".json") || continue
        row = JSON3.read(read(path, String))
        id, result = row.identity, row.result
        cfg = id.configuration
        options = result.effective_configuration.phalcon
        @assert cfg.benchmark == "strings" && cfg.algorithm == "phalcon" path
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

function acceptance_performance(records, common, field, xlabel)
    costs = [getproperty(rows[key], field) for rows in records for key in common]
    lower, upper = minimum(costs) / 1.15, maximum(costs) * 1.08
    @assert lower > 0
    weights = repetition_weights(common)
    panels = map(((:test, "Held-out examples"), (:train, "Training examples"))) do (split, title)
        ax = panel(title; xlabel, ylabel=split === :test ? "Folds solved" : "",
            xscale=:log10, xlims=(lower, upper), ylims=(0, 103), yticks=0:20:100,
            yformatter=y -> "$(round(Int, y))%", legend=split === :train ? :topleft : false,
            legend_title="Threshold", left_margin=5mm, bottom_margin=4mm)
        for (i, threshold) in enumerate(THRESHOLDS)
            rows = records[i]
            events = sort!([(getproperty(rows[key], field), weights[key[1]])
                for key in common if getproperty(rows[key], split)])
            x = [lower; first.(events); upper]
            y = [0; cumsum(last.(events)); sum(last, events; init=0.0)]
            plot_steps!(ax, x, y, COLORS[i], MARKERS[i], i, :solid; label=string(threshold))
        end
        ax
    end
    return plot(panels...; layout=(1, 2), size=(PAPER_WIDTH, 235))
end

function property_count_plots(records, common)
    weights = repetition_weights(common)
    max_properties = maximum(rows[key].properties for rows in records for key in common if rows[key].train)
    last_exact_bin = 20
    histogram = panel("Held-out solves by property count";
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
        isnothing(average) || push!(means, (average, COLORS[i]))
        stephist!(histogram, min.(counts, last_exact_bin + 1); bins=-0.5:1:(last_exact_bin + 1.5),
            color=COLORS[i], linestyle=LINE_STYLES[mod1(i, length(LINE_STYLES))],
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
                COLORS[i], MARKERS[i], i, :solid; label=string(threshold))
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
            plot!(ax, eachindex(ranges), collect(means); color=COLORS[i], marker=MARKERS[i],
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
        scatter!(ax, observed .- 1, counts[observed]; color=COLORS[i],
            markersize=1.5, markerstrokewidth=0)
        ax
    end
    return plot(panels...; layout=(3, 2), ylims=(0.8, max(12_000, 1.25 * maximum(maxima))),
        size=(PAPER_WIDTH, 515))
end

function plot_acceptance(root=ACCEPTANCE_ROOT, baseline=ACCEPTANCE_BASELINE)
    records = map(THRESHOLDS) do threshold
        directory = threshold == 1 ? joinpath(baseline, "strings", "pop-100.runs", "results") :
            joinpath(root, "strings", "threshold-$threshold.runs", "results")
        acceptance_records(directory, threshold)
    end
    base = first(records)
    common = sort!(collect(intersect((Set(keys(rows)) for rows in records)...)))
    isempty(common) && error("No matched fold-runs across thresholds")
    for rows in records, (key, row) in rows
        @assert (base[key].seed, base[key].split) == (row.seed, row.split) key
    end
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
    save_figure(acceptance_performance(records, common, :seconds, "Execution time per fold (s)"),
        output, "01_execution_time")
    save_figure(acceptance_performance(records, common, :programs, "Programs enumerated per fold"),
        output, "02_program_enumerations")
    histogram, cumulative = property_count_plots(records, common)
    save_figure(histogram, output, "03_properties_histogram")
    save_figure(cumulative, output, "04_properties_vs_accuracy")
    save_figure(acceptance_iteration_timing(records, common), output, "05_iteration_timing")
    save_figure(property_agreement_counts(records, common), output, "06_property_agreement")
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) <= 2 || error("Usage: plot_phalcon_acceptance.jl [snapshot_dir] [baseline_dir]")
    plot_acceptance(ARGS...)
end
