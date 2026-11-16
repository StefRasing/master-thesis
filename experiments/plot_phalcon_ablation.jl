# julia --project=. experiments/plot_phalcon_ablation.jl [results_dir] [output_dir] [--bounds] [--common-folds]
# Defaults to the five-run DAIC dataset, with figures written to its plots/ directory.

ENV["GKSwstype"] = get(ENV, "GKSwstype", "100")

using JSON3
using Plots
using Plots.PlotMeasures: mm

const DOMAINS = (("strings", "Strings"), ("bitvectors", "Bitvectors"))
const COLORS = ("#0072B2", "#D55E00", "#009E73", "#8E549F", "#B27900", "#4B586B")
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

panel(title; options...) = plot(; title, titlefontsize=11, guidefontsize=9,
    tickfontsize=8, legendfontsize=8, framestyle=:box,
    left_margin=5mm, bottom_margin=7mm, options...)

function save_figure(figure, output, name)
    for extension in ("pdf", "png", "svg")
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
    series_label=string, legend_title="Population / split", domains=DOMAINS)
    lower, upper = extrema(getproperty(fold, field)
        for groups in values(data) for folds in values(groups) for fold in values(folds)
        if !ismissing(getproperty(fold, field)) && getproperty(fold, field) > 0)
    limits = (lower / 1.3, upper * 1.12)
    decades = ceil(Int, log10(limits[1])):floor(Int, log10(limits[2]))
    ticks = (10.0 .^ decades, ["10^{$exponent}" for exponent in decades])
    panels = map(domains) do (domain, title)
        ax = panel(title; xscale=:log10, xlims=limits, xticks=ticks, ylims=(0, 103), yticks=0:20:100, xlabel=x_label,
            ylabel=domain == first(domains)[1] ? "Folds solved" : "",
            legend=domain == last(domains)[1] ? :topleft : false,
            legend_title, yformatter=y -> "$(round(Int, y))%")
        if show_bounds
            for (key, color) in zip(series, COLORS)
                groups = data[domain, key]
                for (criterion, alpha) in ((:solved, 0.14), (:training_solved, 0.07))
                    budgets, worst, best = repetition_bounds(groups, field, criterion, limits)
                    plot_bounds!(ax, budgets, worst, best; color, alpha)
                end
            end
        end
        for (key, color) in zip(series, COLORS)
            groups = data[domain, key]
            fold_counts = Dict{Int,Int}()
            for ((run, _), folds) in groups
                fold_counts[run] = get(fold_counts, run, 0) + length(folds)
            end
            for (criterion, linestyle) in ((:solved, :solid), (:training_solved, :dash))
                events = sort!([(getproperty(fold, field), 100 / (length(fold_counts) * fold_counts[run]))
                    for ((run, _), folds) in groups for fold in values(folds) if getproperty(fold, criterion)])
                costs = first.(events)
                @assert all(>(0), costs) "Solved folds must have positive costs on the log axis."
                accuracy = cumsum(last.(events))
                plot!(ax, [limits[1]; costs; limits[2]], [0; accuracy; sum(last, events; init=0.0)];
                    seriestype=:steppost, color, linestyle, linewidth=2,
                    label=criterion === :solved ? series_label(key) : false)
            end
        end
        if domain == last(domains)[1]
            plot!(ax, [NaN], [NaN]; color=:black, linewidth=2, label="Test")
            plot!(ax, [NaN], [NaN]; color=:black, linewidth=2, linestyle=:dash, label="Training")
            if show_bounds
                plot!(ax, [NaN], [NaN]; seriestype=:shape, color=:gray, fillalpha=0.3,
                    linealpha=0, label="Best–worst range")
            end
        end
        ax
    end
    return plot(panels...; layout=(1, length(panels)), link=:y,
        size=(length(panels) == 1 ? 720 : 1050, 440))
end

function property_enumerations(data, populations; solved::Bool)
    width = 0.72 / length(populations)
    labels = ["1–9", "10–99", "100–999", "1,000–10,000", "No 1-agreement"]
    panels = map(DOMAINS) do (domain, title)
        outcome = solved ? "Test solved" : "Test unsolved"
        ax = panel("$title · $outcome"; xlabel="Candidates enumerated before first 1-agreement property",
            ylabel=domain == "strings" ? "Property invention attempts" : "", legend=domain == "bitvectors" ? :topleft : false,
            legend_title="Population size", xticks=(1:5, labels), xrotation=15, xlims=(0.5, 5.5))
        for (i, (population, color)) in enumerate(zip(populations, COLORS))
            counts = zeros(Int, 5)
            for folds in values(data[domain, population]), fold in values(folds)
                fold.solved == solved || continue
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
                color, linealpha=0, label=string(population))
        end
        vline!(ax, [4.5]; color=:gray, alpha=0.4, label=false)
        ax
    end
    return plot(panels...; layout=(1, 2), size=(1140, 450))
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
        ax = panel("$(title) · Population $(population) · Test solved";
            xlabel=population == last(populations) ? "Phalcon iteration" : "",
            ylabel=domain == "strings" ? "Mean duration (s)" : "",
            legend=(domain == "bitvectors" && population == first(populations)) ? :topleft : false,
            ylims=(0, 25), yticks=0:5:25, iteration_axis...)
        plot!(ax, mean_phase_times(groups, :search); label="Program search", color=COLORS[1],
            linewidth=2, marker=:none)
        plot!(ax, mean_phase_times(groups, :invention); label="Property invention", color=COLORS[2],
            linewidth=2, marker=:none)
        push!(panels, ax)
    end
    return plot(panels...; layout=(length(populations), 2), link=:all, size=(1050, 260 * length(populations)), left_margin=9mm)
end

function properties_used(data, populations)
    max_used = maximum((count(>(0), fold.agreements) for groups in values(data)
        for folds in values(groups) for fold in values(folds) if fold.solved); init=20)
    edges = -0.5:1:(max_used + 0.5)
    x = repeat(collect(edges); inner=2)[2:end-1]
    panels = map(DOMAINS) do (domain, title)
        ax = panel(title; xlabel="Properties used per fold",
            ylabel=domain == "strings" ? "Solved fold-runs" : "",
            legend=domain == "bitvectors" ? :topright : false, legend_title="Population size",
            yscale=:log10, xlims=(first(edges), last(edges)))
        for (population, color) in zip(populations, COLORS)
            counts = zeros(Int, max_used + 1)
            for folds in values(data[domain, population]), fold in values(folds)
                fold.solved || continue
                counts[1 + count(>(0), fold.agreements)] += 1
            end
            heights = [count == 0 ? NaN : Float64(count) for count in counts]
            plot!(ax, x, repeat(heights; inner=2); color, label=string(population), linewidth=2)
        end
        ax
    end
    return plot(panels...; layout=(1, 2), link=:y, size=(1050, 440))
end

function properties_accuracy(data, populations)
    max_used = maximum((count(>(0), fold.agreements) for groups in values(data)
        for folds in values(groups) for fold in values(folds) if fold.solved || fold.training_solved); init=20)
    tick_counts = filter(<=(max_used), [0, 1, 2, 5, 10, 20, 50, 100, 200, 500])
    panels = map(DOMAINS) do (domain, title)
        ax = panel(title; xlabel="Properties used per fold (log scale of count + 1)",
            ylabel=domain == "strings" ? "Folds solved" : "",
            legend=domain == "bitvectors" ? :topleft : false, legend_title="Population / split",
            xscale=:log10, xlims=(1, max_used + 2), xticks=(tick_counts .+ 1, string.(tick_counts)),
            ylims=(0, 103), yticks=0:20:100, yformatter=y -> "$(round(Int, y))%")
        for (population, color) in zip(populations, COLORS)
            totals = Dict{Int,Int}()
            for ((run, _), folds) in data[domain, population]
                totals[run] = get(totals, run, 0) + length(folds)
            end
            for (criterion, linestyle) in ((:solved, :solid), (:training_solved, :dash))
                counts = zeros(max_used + 1)
                for ((run, _), folds) in data[domain, population], fold in values(folds)
                    getproperty(fold, criterion) || continue
                    used = count(>(0), fold.agreements)
                    counts[used + 1] += 100 / (length(totals) * totals[run])
                end
                accuracy = cumsum(counts)
                plot!(ax, 1:(max_used + 2), [accuracy; last(accuracy)];
                    seriestype=:steppost, color, linestyle, linewidth=2,
                    label=criterion === :solved ? string(population) : false)
            end
        end
        if domain == "bitvectors"
            plot!(ax, [NaN], [NaN]; color=:black, linewidth=2, label="Test")
            plot!(ax, [NaN], [NaN]; color=:black, linewidth=2, linestyle=:dash, label="Training")
        end
        ax
    end
    return plot(panels...; layout=(1, 2), link=:y, size=(1050, 440))
end

function property_agreements(data, populations)
    max_agreement = maximum((agreement for groups in values(data)
        for folds in values(groups) for fold in values(folds) for agreement in fold.agreements); init=1)
    cutoffs = [n for n in [1:10; 25; 50; 100; 250] if n < max_agreement]
    push!(cutoffs, max_agreement)
    starts = [1; cutoffs[1:end-1] .+ 1]
    labels = [lo == hi ? string(lo) : "$(lo)–$(hi)" for (lo, hi) in zip(starts, cutoffs)]
    bins = eachindex(cutoffs)
    width = 0.8 / length(populations)
    panels = map(DOMAINS) do (domain, title)
        ax = panel(title; xlabel="Agreement of selected property",
            ylabel=domain == "strings" ? "Properties selected" : "",
            legend=domain == "bitvectors" ? :topright : false, legend_title="Population size",
            xticks=(bins, labels), xrotation=25, xlims=(0.5, length(bins) + 0.5))
        for (i, (population, color)) in enumerate(zip(populations, COLORS))
            counts = zeros(Int, length(bins))
            for folds in values(data[domain, population]), fold in values(folds), agreement in fold.agreements
                agreement > 0 || continue  # Zero encodes a failed attempt.
                counts[searchsortedfirst(cutoffs, agreement)] += 1
            end
            offset = (i - (length(populations) + 1) / 2) * width
            bar!(ax, bins .+ offset, counts; bar_width=0.94width,
                color, linealpha=0, label=string(population))
        end
        ax
    end
    return plot(panels...; layout=(1, 2), size=(1140, 450))
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
