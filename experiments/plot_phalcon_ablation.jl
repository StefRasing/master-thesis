# julia --project=. experiments/plot_phalcon_ablation.jl [results_dir] [output_dir] [--bounds] [--common-folds]
# Defaults to the five-run DAIC dataset, with figures written to its plots/ directory.

ENV["GKSwstype"] = get(ENV, "GKSwstype", "100")

using JSON3
using Plots
using Plots.PlotMeasures: mm

const DOMAINS = (("strings", "Strings"), ("bitvectors", "Bitvectors"))
# The AAAI text block is 7 inches wide, with a 0.375-inch gutter.
# GR's PDF backend treats the canvas dimensions as PDF points.
const PAPER_WIDTH = 504
const COLUMN_WIDTH = 238
const COLORS = ("#111111", "#285B80", "#7A3D16", "#5F4175", "#21604A", "#575757")
const MARKERS = (:circle, :rect, :diamond, :utriangle, :dtriangle, :star5)
const LINE_STYLES = (:solid, :dash, :dot, :dashdot, :dashdotdot)
const BAR_SHADES = ("#151515", "#454545", "#707070", "#999999", "#C1C1C1", "#E7E7E7")
const DEFAULT_RESULTS = normpath(joinpath(@__DIR__, "..", "data", "phalcon_ablation",
    "daic-population-five-runs-20261111"))

function load_problem_runs(results_dir, domain, population)
    directory = joinpath(results_dir, domain, "pop-$(population).runs", "results")
    groups = Dict{Tuple{Int,String},Dict{Int,NamedTuple}}()
    for path in readdir(directory; join=true)
        endswith(path, ".json") || continue
        record = JSON3.read(read(path, String))
        identity, result = record.identity, record.result
        config = identity.configuration
        @assert config.benchmark == domain && config.iterator_options.population_size == population path
        @assert result.solved_test_examples == (result.correct_test_examples == result.test_examples) path
        @assert length(result.heuristic) == length(result.property_invention_durations) path
        key = (parse(Int, config.run), String(identity.problem))
        folds = get!(groups, key, Dict{Int,NamedTuple}())
        @assert !haskey(folds, identity.fold) path
        folds[identity.fold] = (;
            solved=result.solved_test_examples,
            training_solved=result.solved_train_examples,
            seconds=Float64(result.execution_time),
            programs=Int(result.programs_enumerated),
            agreements=Int[prop == "failed" ? 0 : prop[2] for prop in result.heuristic],
            property_indices=Int[prop == "failed" ? 0 : prop[3] for prop in result.heuristic],
            search=Float64.(result.program_synthesis_durations),
            invention=Float64.(result.property_invention_durations),
            fold_count=Int(result.folds),
            test_indices=Tuple(identity.test_indices),
        )
    end
    isempty(groups) && error("No results in $(directory)")
    return groups
end

# At native size, GR maps these font sizes to at least 11 PDF points.
# Its raster scaling yields about 317 pixels per inch at the same placement size.
panel(title; options...) = plot(; title, fontfamily="Helvetica", titlefontsize=9,
    guidefontsize=8, tickfontsize=7, legendfontsize=7, legendtitlefontsize=7,
    framestyle=:box, foreground_color=:black, background_color=:white,
    grid=false, left_margin=2mm, right_margin=2mm, bottom_margin=2mm,
    dpi=440, options...)

# Marks at spaced budgets identify the method in grayscale without obscuring the steps.
function plot_steps!(ax, x, y, color, marker, series_index, linestyle; label=false)
    plot!(ax, x, y; seriestype=:steppost, color, linestyle, linewidth=1.5, label=false)
    lower, upper = log10(first(x)), log10(last(x))
    budgets = 10 .^ (lower .+ (upper - lower) .* ((1:6) .+ (series_index - 3.5) / 8) ./ 7)
    levels = y[searchsortedlast.(Ref(x), budgets)]
    scatter!(ax, budgets, levels; color, marker, markersize=2, markerstrokewidth=0.65,
        markerstrokecolor=color, label)
end

function save_figure(figure, output, name)
    gs = Sys.which("gs")
    isnothing(gs) && error("Ghostscript (gs) is required to embed the plot's PDF fonts.")
    mktempdir() do temp
        raw = joinpath(temp, "raw.pdf")
        embedded = joinpath(temp, "embedded.pdf")
        savefig(figure, raw)
        run(`$gs -q -dBATCH -dNOPAUSE -sDEVICE=pdfwrite -dEmbedAllFonts=true
            -dSubsetFonts=true -sOutputFile=$embedded -c '<</NeverEmbed []>> setdistillerparams' -f $raw`)
        cp(embedded, joinpath(output, "$name.pdf"); force=true)
    end
    for extension in ("png", "svg")
        savefig(figure, joinpath(output, "$(name).$(extension)"))
    end
end

function repetition_bounds(groups, field, criterion, limits)
    by_split = Dict{Tuple{String,Int},Vector{Float64}}()
    for ((_, problem), folds) in groups, (index, fold) in folds
        costs = get!(by_split, (problem, index), Float64[])
        push!(costs, getproperty(fold, criterion) ? getproperty(fold, field) : Inf)
    end
    # Infinity denotes a repetition that never solved the split within its budget.
    best = sort!([minimum(costs) for costs in values(by_split)])
    worst = sort!([maximum(costs) for costs in values(by_split)])
    budgets = sort!(unique([limits[1]; filter(isfinite, best); filter(isfinite, worst); limits[2]]))
    percentages(costs) = [100 * searchsortedlast(costs, budget) / length(costs) for budget in budgets]
    return budgets, percentages(worst), percentages(best)
end

function plot_bounds!(ax, budgets, worst, best; color, alpha)
    # Duplicate the coordinates at each jump so the filled region follows the stairs.
    x = [budgets[1]; repeat(budgets[2:end]; inner=2)]
    stair(values) = [repeat(values[1:end-1]; inner=2); values[end]]
    plot!(ax, x, stair(best); fillrange=stair(worst), fillcolor=color, fillalpha=alpha,
        linealpha=0, label=false)
end

function performance(data, series, field, x_label; show_bounds=false,
    series_label=string, legend_title="Population / split", domains=DOMAINS, training_overlays=(), arc_placeholder=false)
    lower, upper = extrema(getproperty(fold, field)
        for groups in values(data) for folds in values(groups) for fold in values(folds)
        if !ismissing(getproperty(fold, field)) && getproperty(fold, field) > 0)
    # Reserve space for data plotted only in the strings panel.
    for overlay in training_overlays
        lower = min(lower, first(overlay.budgets))
        upper = max(upper, last(overlay.budgets))
    end
    limits = (lower / 1.3, upper * 1.12)
    first_decade, last_decade = ceil(Int, log10(limits[1])), floor(Int, log10(limits[2]))
    decades = first_decade:(arc_placeholder ? 3 : last_decade - first_decade >= 6 ? 2 : 1):last_decade
    ticks = (10.0 .^ decades, ["1e$exponent" for exponent in decades])
    solve_formatter = arc_placeholder ? y -> string(round(Int, y)) : y -> "$(round(Int, y))%"
    legend_position = length(domains) == 1 ? :outerbottom : :topleft
    legend_domain = arc_placeholder ? nothing : last(domains)[1]
    curve_end = arc_placeholder ? nextfloat(limits[2] * 1.01) : limits[2]
    solve_limits = arc_placeholder ? (-3, 103) : (0, 103)
    compact = arc_placeholder ? (; titlefontsize=7, tickfontsize=5, guidefontsize=6,
        left_margin=-1mm, right_margin=0mm, top_margin=-1mm, bottom_margin=-1mm) : (;)
    endpoints = Dict(domain => Tuple{Float64,String,Symbol}[] for (domain, _) in domains)
    panels = map(domains) do (domain, title)
        heading = arc_placeholder && domain == "bitvectors" ? "Bit-vectors" : title
        ax = panel(heading; xscale=:log10, xlims=limits, xticks=ticks,
            ylims=solve_limits, yticks=arc_placeholder ? [0, 50, 100] : 0:20:100,
            xlabel=arc_placeholder ? "" : x_label,
            ylabel=!arc_placeholder && domain == first(domains)[1] ?
                (isempty(training_overlays) ? "Folds solved" : "Solved") : "",
            legend=domain == legend_domain ? legend_position : false,
            legend_column=length(domains) == 1 ? 2 : 1,
            legend_title, yformatter=solve_formatter, compact...)
        if show_bounds
            for (key, color) in zip(series, COLORS)
                groups = data[domain, key]
                for (criterion, alpha) in ((:solved, 0.14), (:training_solved, 0.07))
                    budgets, worst, best = repetition_bounds(groups, field, criterion, limits)
                    plot_bounds!(ax, budgets, worst, best; color, alpha)
                end
            end
        end
        for (i, (key, color, marker)) in enumerate(zip(series, COLORS, MARKERS))
            groups = data[domain, key]
            fold_counts = Dict{Int,Int}()
            for ((run, _), folds) in groups
                fold_counts[run] = get(fold_counts, run, 0) + length(folds)
            end
            for (criterion, linestyle) in ((:solved, :solid), (:training_solved, :dot))
                events = sort!([(getproperty(fold, field), 100 / (length(fold_counts) * fold_counts[run]))
                    for ((run, _), folds) in groups for fold in values(folds) if getproperty(fold, criterion)])
                costs = first.(events)
                @assert all(>(0), costs) "Solved folds must have positive costs on the log axis."
                accuracy = cumsum(last.(events))
                final_accuracy = sum(last, events; init=0.0)
                if arc_placeholder
                    push!(endpoints[domain], (final_accuracy, color, marker))
                end
                plot_steps!(ax, [limits[1]; costs; curve_end],
                    [0; accuracy; final_accuracy], color, marker, i, linestyle;
                    label=criterion === :solved ? series_label(key) : false)
            end
        end
        if domain == "strings"
            for (i, overlay) in enumerate(training_overlays)
                index = length(series) + i
                color, marker = COLORS[index], MARKERS[index]
                if arc_placeholder
                    push!(endpoints[domain], (last(overlay.percentages), color, marker))
                end
                label = domain == legend_domain ? overlay.label : false
                if overlay.estimated
                    plot!(ax, overlay.budgets, overlay.percentages; color, marker, linestyle=:dash,
                        linewidth=1.8, markersize=2.3, markerstrokewidth=0.7,
                        markerstrokecolor=:white, label)
                else
                    plot_steps!(ax, [limits[1]; overlay.budgets; curve_end],
                        [0; overlay.percentages; last(overlay.percentages)],
                        color, marker, index, :dot; label)
                end
            end
        end
        if domain == legend_domain
            if domain != "strings"
                for (i, overlay) in enumerate(training_overlays)
                    index = length(series) + i
                    scatter!(ax, [NaN], [NaN]; color=COLORS[index], marker=MARKERS[index],
                        markersize=2, markerstrokewidth=0.65, label=overlay.label)
                end
            end
            plot!(ax, [NaN], [NaN]; color=:black, linewidth=2, label="Test")
            plot!(ax, [NaN], [NaN]; color=:black, linewidth=2, linestyle=:dot, label="Training")
            if show_bounds
                plot!(ax, [NaN], [NaN]; seriestype=:shape, color=:gray, fillalpha=0.3,
                    linealpha=0, label="Run range")
            end
        end
        ax
    end
    if arc_placeholder
        arc = panel("ARC-AGI-1"; xscale=:log10, xlims=limits, xticks=ticks, ylims=solve_limits,
            yticks=[0, 50, 100], yformatter=solve_formatter, legend=false, compact...)
        annotate!(arc, sqrt(prod(limits)), 50, Plots.text("Pending", 5, :gray))
        key = plot(; framestyle=:none, legend=false, grid=false, xlims=(0, 1),
            ylims=(0.5, 8.5), margins=0mm, fontfamily="Helvetica")
        methods = [(series_label(method), color, marker) for (method, color, marker) in zip(series, COLORS, MARKERS)]
        for (i, overlay) in enumerate(training_overlays)
            index = length(series) + i
            push!(methods, (overlay.label, COLORS[index], MARKERS[index]))
        end
        order = ("Phalcon", "Informed", "Naive", "CrossBeam", "BUSTLE (est.)")
        sort!(methods; by=method -> something(findfirst(==(first(method)), order), length(order) + 1))
        for (i, (label, color, marker)) in enumerate(methods)
            y = 9 - i
            scatter!(key, [0.24], [y]; color, marker, markersize=1.8, markerstrokewidth=0.5)
            annotate!(key, 0.39, y, Plots.text(label, 5, :black, :left))
        end
        y = 8 - length(methods)
        for (label, linestyle) in (("Test", :solid), ("Training", :dot))
            plot!(key, [0.15, 0.33], [y, y]; color=:black, linestyle, linewidth=1.2)
            annotate!(key, 0.39, y, Plots.text(label, 5, :black, :left))
            y -= 1
        end
        function endpoint_labels(domain)
            labels = sort(endpoints[domain]; by=first, rev=true)
            gutter = plot(; framestyle=:none, legend=false, grid=false,
                xlims=(0, 1), ylims=(solve_limits[1], solve_limits[2]), margins=0mm,
                ticks=nothing, showaxis=false, left_margin=-2mm, right_margin=-1mm)
            for ((value, color, marker), y) in zip(labels, range(95, 8; length=length(labels)))
                scatter!(gutter, [0.08], [y]; color, marker, markersize=1.6, markerstrokewidth=0.4)
                label = string(round(value; digits=1), "%")
                annotate!(gutter, 0.19, y, Plots.text(label, 4, color, :left))
            end
            return gutter
        end
        heading = field === :seconds ? "Solved (%) vs. execution time (s)" : "Solved (%) vs. programs enumerated"
        layout = grid(2, 1; heights=[0.53, 0.47])
        layout[1, 1] = grid(1, 4; widths=[0.39, 0.11, 0.39, 0.11])
        layout[2, 1] = grid(1, 3; widths=[0.39, 0.11, 0.50])
        blank = plot(; framestyle=:none, legend=false, grid=false, margins=0mm)
        return plot(panels[1], endpoint_labels("strings"), panels[2], endpoint_labels("bitvectors"),
            arc, blank, key; layout, size=(COLUMN_WIDTH, 285), dpi=440,
            plot_title=heading, plot_titlevspan=0.08, plot_titlefontsize=8, plot_titlefontfamily="Helvetica")
    end
    return plot(panels...; layout=(1, length(panels)), link=:y,
        size=(length(panels) == 1 ? COLUMN_WIDTH : PAPER_WIDTH, 240))
end

function property_enumerations(data, populations; solved::Union{Bool,Nothing}=nothing)
    width = 0.72 / length(populations)
    labels = ["1-9", "10-99", "100-999", "1k-10k", "No hit"]
    panels = map(DOMAINS) do (domain, title)
        heading = isnothing(solved) ? title : "$title · Test $(solved ? "solved" : "unsolved")"
        ax = panel(heading; xlabel="Candidates to first 1-agreement",
            ylabel=domain == "strings" ? "Property invention attempts" : "",
            yformatter=y -> string(round(Int, y)), legend=domain == "bitvectors" ? :topleft : false,
            legend_title="Population", bottom_margin=6mm, xticks=(1:5, labels), xrotation=25, xlims=(0.5, 5.5))
        for (i, (population, color)) in enumerate(zip(populations, BAR_SHADES))
            counts = zeros(Int, 5)
            for folds in values(data[domain, population]), fold in values(folds)
                isnothing(solved) || fold.solved == solved || continue
                for (agreement, index) in zip(fold.agreements, fold.property_indices)
                    if agreement == 1
                        @assert 1 <= index <= 10_000
                        counts[searchsortedfirst([9, 99, 999, 10_000], index)] += 1
                    else
                        counts[5] += 1
                    end
                end
            end
            bar!(ax, (1:5) .+ (i - (length(populations) + 1) / 2) * width, counts; bar_width=0.94width,
                color, linecolor=:black, linewidth=1, label=string(population))
        end
        vline!(ax, [4.5]; color=:black, linestyle=:dot, linewidth=1, label=false)
        ax
    end
    return plot(panels...; layout=(1, 2), size=(PAPER_WIDTH, 247))
end

function mean_phase_times(groups, phase; max_iteration=50)
    durations = [getproperty(fold, phase) for folds in values(groups)
        for fold in values(folds) if fold.solved]
    total = zeros(min(max_iteration, maximum(length, durations; init=0)))
    counts = zeros(Int, length(total))
    for times in durations, (i, duration) in enumerate(Iterators.take(times, max_iteration))
        total[i] += duration
        counts[i] += 1
    end
    return total ./ counts
end

function iteration_timing(data, populations)
    panels = Plots.Plot[]
    iteration_axis = (; xlims=(1, 50), xticks=[1, 10, 20, 30, 40, 50])
    for population in populations, (domain, title) in DOMAINS
        groups = data[domain, population]
        ax = panel("$title · Pop. $population";
            xlabel=population == last(populations) ? "Iteration (test-solved folds)" : "",
            ylabel=domain == "strings" ? "Mean time (s)" : "",
            legend=(domain == "bitvectors" && population == first(populations)) ? :topleft : false,
            ylims=(0, 25), yticks=0:10:20, iteration_axis...)
        plot!(ax, mean_phase_times(groups, :search); label="Program search", color=COLORS[1],
            linewidth=2, marker=:none)
        plot!(ax, mean_phase_times(groups, :invention); label="Property invention", color=COLORS[2],
            linewidth=2, linestyle=:dash)
        push!(panels, ax)
    end
    return plot(panels...; layout=(length(populations), 2), link=:all, size=(PAPER_WIDTH, 105 * length(populations)))
end

function properties_used(data, populations)
    max_used = maximum((count(>(0), fold.agreements) for groups in values(data)
        for folds in values(groups) for fold in values(folds) if fold.solved); init=20)
    edges = -0.5:1:(max_used + 0.5)
    x = repeat(collect(edges); inner=2)[2:end-1]
    panels = map(DOMAINS) do (domain, title)
        ax = panel(title; xlabel="Properties used per fold",
            ylabel=domain == "strings" ? "Solved fold-runs" : "",
            legend=domain == "bitvectors" ? :topright : false, legend_column=2, legend_title="Population",
            yscale=:log10, yformatter=y -> string(round(Int, y)), xlims=(first(edges), last(edges)))
        for (i, (population, color, linestyle)) in enumerate(zip(populations, COLORS, Iterators.cycle(LINE_STYLES)))
            counts = zeros(Int, max_used + 1)
            for folds in values(data[domain, population]), fold in values(folds)
                fold.solved || continue
                counts[1 + count(>(0), fold.agreements)] += 1
            end
            heights = [count == 0 ? NaN : Float64(count) for count in counts]
            plot!(ax, x, repeat(heights; inner=2); color, linestyle,
                label=i == 6 ? false : string(population), linewidth=1.5)
            if i == 6
                scatter!(ax, 0:max_used, heights; color, marker=last(MARKERS), markersize=2,
                    markerstrokewidth=0.65, markerstrokecolor=color, label=string(population))
            end
        end
        ax
    end
    return plot(panels...; layout=(1, 2), link=:y, size=(PAPER_WIDTH, 216))
end

function properties_accuracy(data, populations)
    max_used = maximum((count(>(0), fold.agreements) for groups in values(data)
        for folds in values(groups) for fold in values(folds) if fold.solved || fold.training_solved); init=20)
    tick_counts = filter(<=(max_used), [0, 1, 2, 5, 10, 20, 50, 100, 200, 500])
    panels = map(DOMAINS) do (domain, title)
        ax = panel(title; xlabel="Properties used per fold",
            ylabel=domain == "strings" ? "Folds solved" : "",
            legend=domain == "bitvectors" ? :topleft : false, legend_title="Population / split",
            xscale=:log10, xlims=(1, max_used + 2), xticks=(tick_counts .+ 1, string.(tick_counts)),
            ylims=(0, 103), yticks=0:20:100, yformatter=y -> "$(round(Int, y))%")
        for (i, (population, color, marker)) in enumerate(zip(populations, COLORS, MARKERS))
            totals = Dict{Int,Int}()
            for ((run, _), folds) in data[domain, population]
                totals[run] = get(totals, run, 0) + length(folds)
            end
            for (criterion, linestyle) in ((:solved, :solid), (:training_solved, :dot))
                counts = zeros(max_used + 1)
                for ((run, _), folds) in data[domain, population], fold in values(folds)
                    getproperty(fold, criterion) || continue
                    used = count(>(0), fold.agreements)
                    counts[used + 1] += 100 / (length(totals) * totals[run])
                end
                accuracy = cumsum(counts)
                plot_steps!(ax, 1:(max_used + 2), [accuracy; last(accuracy)], color, marker, i, linestyle;
                    label=criterion === :solved ? string(population) : false)
            end
        end
        if domain == "bitvectors"
            plot!(ax, [NaN], [NaN]; color=:black, linewidth=2, label="Test")
            plot!(ax, [NaN], [NaN]; color=:black, linewidth=2, linestyle=:dot, label="Training")
        end
        ax
    end
    return plot(panels...; layout=(1, 2), link=:y, size=(PAPER_WIDTH, 216))
end

function property_agreements(data, populations)
    max_agreement = maximum((agreement for groups in values(data)
        for folds in values(groups) for fold in values(folds) for agreement in fold.agreements); init=1)
    cutoffs = [n for n in [1:10; 25; 50; 100; 250] if n < max_agreement]
    push!(cutoffs, max_agreement)
    starts = [1; cutoffs[1:end-1] .+ 1]
    labels = [lo == hi ? string(lo) : "$(lo)-$(hi)" for (lo, hi) in zip(starts, cutoffs)]
    bins = eachindex(cutoffs)
    width = 0.8 / length(populations)
    panels = map(DOMAINS) do (domain, title)
        ax = panel(title; xlabel="Agreement of selected property",
            ylabel=domain == "strings" ? "Properties selected" : "",
            legend=domain == "bitvectors" ? :topright : false,
            legend_title="Population", bottom_margin=8mm, yformatter=y -> string(round(Int, y)),
            xticks=(bins, labels), xrotation=55, xlims=(0.5, length(bins) + 0.5))
        for (i, (population, color)) in enumerate(zip(populations, BAR_SHADES))
            counts = zeros(Int, length(bins))
            for folds in values(data[domain, population]), fold in values(folds), agreement in fold.agreements
                agreement > 0 || continue  # Zero encodes a failed attempt.
                counts[searchsortedfirst(cutoffs, agreement)] += 1
            end
            offset = (i - (length(populations) + 1) / 2) * width
            bar!(ax, bins .+ offset, counts; bar_width=0.94width,
                color, linecolor=:black, linewidth=1, label=string(population))
        end
        ax
    end
    return plot(panels...; layout=(1, 2), size=(PAPER_WIDTH, 247))
end

function plot_ablation(results_dir=DEFAULT_RESULTS, output_dir=joinpath(results_dir, "plots");
        show_bounds=false, common_folds=false)
    populations = sort!([parse(Int, match(r"^pop-(\d+)\.runs$", name)[1])
        for name in readdir(joinpath(results_dir, first(DOMAINS)[1]))
        if occursin(r"^pop-\d+\.runs$", name)])
    @assert 1 <= length(populations) <= length(COLORS)
    data = Dict()
    for (domain, _) in DOMAINS
        cohorts = Set{Tuple{String,Int,Tuple}}[]
        for population in populations
            groups = load_problem_runs(results_dir, domain, population)
            data[domain, population] = groups
            @assert Set(run for (run, _) in keys(groups)) == Set(1:5)
            for run in 1:5
                push!(cohorts, Set((problem, index, fold.test_indices)
                    for ((id, problem), folds) in groups if id == run for (index, fold) in folds))
            end
        end
        shared = intersect(cohorts...)
        @assert !isempty(shared)
        @assert common_folds || all(==(shared), cohorts) "Incomplete or inconsistent fold coverage. Use --common-folds for matched analysis."
        println("$(domain): $(length(shared)) shared folds per repetition")
        for population in populations
            groups = data[domain, population]
            for ((run, problem), folds) in groups
                filter!(pair -> (problem, first(pair), last(pair).test_indices) in shared, folds)
            end
            filter!(pair -> !isempty(last(pair)), groups)
            folds = Iterators.flatten(values(folds) for folds in values(groups))
            passed = count(fold -> fold.solved, folds)
            total = sum(length, values(groups))
            @assert total == 5 * length(shared)
            println("$(domain) population $(population): $(passed)/$(total) folds solved")
        end
    end
    mkpath(output_dir)
    save_figure(performance(data, populations, :seconds, "Execution time per fold (s)"; show_bounds),
        output_dir, "01_execution_time")
    save_figure(performance(data, populations, :programs, "Programs enumerated per fold"; show_bounds),
        output_dir, "02_program_enumerations")
    save_figure(property_enumerations(data, populations), output_dir, "03_property_enumerations")
    save_figure(property_enumerations(data, populations; solved=true),
        output_dir, "03a_property_enumerations_solved")
    save_figure(property_enumerations(data, populations; solved=false),
        output_dir, "03b_property_enumerations_unsolved")
    save_figure(iteration_timing(data, populations), output_dir, "04_iteration_timing")
    save_figure(properties_used(data, populations), output_dir, "05_properties_used")
    save_figure(properties_accuracy(data, populations), output_dir, "06_accuracy_vs_properties_used")
    save_figure(property_agreements(data, populations), output_dir, "07_property_agreements")
end

if abspath(PROGRAM_FILE) == @__FILE__
    paths = filter(arg -> arg ∉ ("--bounds", "--common-folds"), ARGS)
    length(paths) <= 2 || error("Usage: plot_phalcon_ablation.jl [results_dir] [output_dir] [--bounds] [--common-folds]")
    plot_ablation(paths...; show_bounds="--bounds" in ARGS, common_folds="--common-folds" in ARGS)
end
