# julia --project=. experiments/plot_phalcon_batch.jl [snapshot_dir] [output_dir] [--bounds]
include("plot_phalcon_ablation.jl")

const BATCH_ROOT = normpath(joinpath(@__DIR__, "..", "data", "phalcon_batch", "daic-20261116"))
const BATCH_CAPS = (5, 10, 20, 40)
const BATCH_BASELINE = joinpath(dirname(DEFAULT_RESULTS), "daic-uncapped-20261112-pop100")
const BATCH_SERIES = (BATCH_CAPS..., :default)
batch_label(key) = key === :default ? "Default Phalcon" : "Batch $key"

function add_default!(data, baseline)
    for (domain, _) in DOMAINS
        groups = load_problem_runs(baseline, domain, 100)
        expected = data[domain, first(BATCH_CAPS)]
        @assert Set(keys(groups)) == Set(keys(expected))
        for (key, folds) in groups
            @assert Set(keys(folds)) == Set(keys(expected[key]))
            for (index, fold) in folds
                @assert fold.test_indices == expected[key][index].test_indices
            end
        end
        data[domain, :default] = groups
    end
    return data
end

function load_batch(snapshot)
    data = Dict()
    reference = Dict()
    for (domain, _) in DOMAINS, cap in BATCH_CAPS
        groups = Dict{Tuple{Int,String},Dict{Int,NamedTuple}}()
        directory = joinpath(snapshot, "results", domain, "properties-$cap.runs", "results")
        for path in readdir(directory; join=true)
            endswith(path, ".json") || continue
            row = JSON3.read(read(path, String))
            id, r = row.identity, row.result
            cfg = id.configuration
            @assert cfg.algorithm == "phalcon_batch" && cfg.benchmark == domain path
            @assert cfg.iterator_options.population_size == 100 && cfg.timeout == 1800 path
            @assert r.effective_configuration.phalcon.max_number_of_properties == cap path
            @assert r.effective_configuration.phalcon.max_property_evaluations == 10_000 path
            @assert r.solved_test_examples == (r.test_examples == r.correct_test_examples) path
            key = (parse(Int, cfg.run), String(id.problem))
            folds = get!(groups, key, Dict{Int,NamedTuple}())
            @assert !haskey(folds, id.fold) path
            @assert length(r.program_synthesis_durations) <= 2 path
            @assert length(r.property_invention_durations) <= 1 path
            folds[id.fold] = (;
                solved=Bool(r.solved_test_examples), training_solved=Bool(r.solved_train_examples),
                seconds=Float64(r.execution_time), programs=Int(r.programs_enumerated),
                agreements=Int[prop[2] for prop in r.heuristic],
                property_indices=Int[prop[3] for prop in r.heuristic],
                search=Float64[x for x in r.program_synthesis_durations],
                invention=Float64[x for x in r.property_invention_durations],
                fold_count=Int(r.folds), test_indices=Tuple(id.test_indices),
            )
        end
        expected = domain == "strings" ? 449 : 755
        @assert Set(first.(keys(groups))) == Set(1:5)
        for run in 1:5
            @assert sum(length(folds) for ((rep, _), folds) in groups if rep == run) == expected
        end
        for folds in values(groups)
            @assert Set(keys(folds)) == Set(1:first(values(folds)).fold_count)
        end
        splits = Dict((run, problem, fold) => r.test_indices
            for ((run, problem), folds) in groups for (fold, r) in folds)
        if !haskey(reference, domain)
            reference[domain] = splits
        end
        @assert reference[domain] == splits
        for ((_, problem, fold), split) in splits
            @assert all(splits[run, problem, fold] == split for run in 1:5)
        end
        data[domain, cap] = groups
        passed = count(r.solved for folds in values(groups) for r in values(folds))
        println("$domain cap $cap: $passed/$(5expected) test-solved fold-runs")
    end
    return data
end

function batch_enumerations(data)
    labels = ["1–9", "10–99", "100–999", "1k–10k", "No hit"]
    panels = map(DOMAINS) do (domain, title)
        ax = panel(title; xlabel="Candidates to first 1-agreement hit",
            ylabel=domain == "strings" ? "Invention attempts" : "",
            legend=domain == "bitvectors" ? :topleft : false, legend_title="Method / batch cap",
            xticks=(1:5, labels), xrotation=25, bottom_margin=6mm)
        peak = 0
        for (i, cap) in enumerate(BATCH_SERIES)
            counts = zeros(Int, 5)
            for folds in values(data[domain, cap]), r in values(folds)
                isempty(r.invention) && continue
                if cap === :default
                    for (agreement, index) in zip(r.agreements, r.property_indices)
                        bin = agreement == 1 ? searchsortedfirst([9, 99, 999, 10_000], index) : 5
                        counts[bin] += 1
                    end
                    continue
                end
                hits = [index for (agreement, index) in zip(r.agreements, r.property_indices) if agreement == 1]
                bin = isempty(hits) ? 5 : searchsortedfirst([9, 99, 999, 10_000], minimum(hits))
                counts[bin] += 1
            end
            peak = max(peak, maximum(counts))
            bar!(ax, (1:5) .+ (i - 3) * 0.15, counts; bar_width=0.14,
                color=BAR_SHADES[i], linecolor=:black, linewidth=0.5, label=batch_label(cap))
        end
        plot!(ax; ylims=(0, 1.15peak))
        ax
    end
    plot(panels...; layout=(1, 2), size=(PAPER_WIDTH, 260))
end

function batch_timing(data)
    panels = map(DOMAINS) do (domain, title)
        ax = panel(title; ylabel=domain == "strings" ? "Mean time per fold (s)" : "",
            xticks=(1:3, ["Initial search", "Total invention", "Later search"]), xrotation=20,
            bottom_margin=6mm, legend=domain == "bitvectors" ? :topleft : false,
            legend_title="Method / batch cap")
        peak = 0.0
        for (i, cap) in enumerate(BATCH_SERIES)
            rows = [r for folds in values(data[domain, cap]) for r in values(folds)]
            # A skipped or unrecorded phase contributes zero to this all-fold mean.
            durations = [
                sum(isempty(r.search) ? 0.0 : r.search[1] for r in rows),
                sum(sum(r.invention; init=0.0) for r in rows),
                sum(sum(Iterators.drop(r.search, 1); init=0.0) for r in rows),
            ] ./ length(rows)
            peak = max(peak, maximum(durations))
            bar!(ax, (1:3) .+ (i - 3) * 0.15, durations; bar_width=0.14,
                color=BAR_SHADES[i], linecolor=:black, linewidth=0.5, label=batch_label(cap))
        end
        plot!(ax; ylims=(0, 1.15peak))
        ax
    end
    plot(panels...; layout=(1, 2), size=(PAPER_WIDTH, 260))
end

function batch_properties(data)
    panels = map(DOMAINS) do (domain, title)
        ax = panel(title; xlabel="Properties used per test-solved fold",
            ylabel=domain == "strings" ? "Solved fold-runs" : "",
            legend=domain == "bitvectors" ? :topright : false, legend_title="Method / batch cap",
            xticks=([0, 5, 10, 15, 20, 21], ["0", "5", "10", "15", "20", "21+"]))
        for (i, cap) in enumerate(BATCH_SERIES)
            counts = zeros(Int, 22)
            for folds in values(data[domain, cap]), r in values(folds)
                r.solved || continue
                counts[min(count(>(0), r.agreements), 21) + 1] += 1
            end
            edges = -0.5:1:21.5
            x = repeat(collect(edges); inner=2)[2:end-1]
            plot!(ax, x, repeat(counts; inner=2); color=COLORS[i],
                linestyle=LINE_STYLES[i], label=batch_label(cap), linewidth=1.5)
        end
        ax
    end
    plot(panels...; layout=(1, 2), size=(PAPER_WIDTH, 245))
end

function add_property_references!(figure, data)
    for (index, (domain, _)) in enumerate(DOMAINS)
        groups = data[domain, :default]
        runs = sort!(unique(first.(keys(groups))))
        for (limit, style, label) in ((1, :dashdot, "Default: at most 1 property"),)
            # Average fold accuracy within each repetition, then across repetitions.
            rates = map(runs) do run
                rows = [r for ((rep, _), folds) in groups if rep == run for r in values(folds)]
                100 * count(r -> r.solved && count(>(0), r.agreements) <= limit, rows) / length(rows)
            end
            level = sum(rates) / length(rates)
            hline!(figure[index], [level]; color="#777777", linestyle=style,
                linewidth=1, label=domain == "bitvectors" ? label : false)
            println("$domain $label: $level%")
        end
    end
    plot!(figure[2]; legendfontsize=5, legendtitlefontsize=5)
    return figure
end

function shared_solves(data, domain, cap)
    batch, default = data[domain, cap], data[domain, :default]
    return [(; run=key[1], batch=r, default=default[key][fold])
        for (key, folds) in batch for (fold, r) in folds
        if r.solved && default[key][fold].solved]
end

function shared_performance(data, field, xlabel)
    panels = Plots.Plot[]
    all_costs = [getproperty(getproperty(pair, method), field)
        for (domain, _) in DOMAINS for cap in BATCH_CAPS
        for pair in shared_solves(data, domain, cap) for method in (:batch, :default)]
    lower, upper = extrema(all_costs)
    @assert lower > 0
    limits = (lower / 1.2, upper * 1.12)
    for (i, cap) in enumerate(BATCH_CAPS), (domain, title) in DOMAINS
        pairs = shared_solves(data, domain, cap)
        run_counts = Dict(run => count(pair -> pair.run == run, pairs) for run in 1:5)
        @assert all(>(0), values(run_counts)) "Every repetition must have shared solves."
        ax = panel("$title · Batch $cap (n=$(length(pairs)))";
            xlabel=cap == last(BATCH_CAPS) ? xlabel : "",
            ylabel=domain == "strings" ? "Shared solves completed" : "",
            xscale=:log10, xlims=limits, ylims=(0, 103), yticks=0:25:100,
            yformatter=y -> "$(round(Int, y))%",
            legend=(i == 1 && domain == "bitvectors") ? :bottomright : false)
        for (method, color, style, label) in (
                (:batch, COLORS[2], :solid, "Batch"),
                (:default, COLORS[1], :dash, "Default Phalcon"))
            events = sort!([(getproperty(getproperty(pair, method), field),
                100 / (5 * run_counts[pair.run])) for pair in pairs])
            levels = cumsum(last.(events))
            @assert isapprox(last(levels), 100; atol=1e-8)
            plot!(ax, [limits[1]; first.(events); limits[2]], [0; levels; 100];
                seriestype=:steppost, color, linestyle=style, linewidth=1.5, label)
        end
        push!(panels, ax)
    end
    return plot(panels...; layout=(4, 2), size=(PAPER_WIDTH, 650))
end

function save_shared_comparisons(data, output)
    save_figure(shared_performance(data, :seconds, "Execution time per fold (s)"),
        output, "06_shared_solves_execution_time")
    save_figure(shared_performance(data, :programs, "Programs enumerated per fold"),
        output, "07_shared_solves_program_enumerations")
    open(joinpath(output, "shared_solves_summary.tsv"), "w") do io
        println(io, "domain\tbatch_cap\tshared_fold_runs\tbatch_faster_time\ttied_time\tbatch_fewer_programs\ttied_programs")
        for (domain, _) in DOMAINS, cap in BATCH_CAPS
            pairs = shared_solves(data, domain, cap)
            faster = count(p -> p.batch.seconds < p.default.seconds, pairs)
            time_ties = count(p -> p.batch.seconds == p.default.seconds, pairs)
            fewer = count(p -> p.batch.programs < p.default.programs, pairs)
            program_ties = count(p -> p.batch.programs == p.default.programs, pairs)
            println(io, join((domain, cap, length(pairs), faster, time_ties, fewer, program_ties), '\t'))
        end
    end
end

function plot_batch(snapshot=BATCH_ROOT, output=joinpath(snapshot, "plots"); show_bounds=false, baseline=BATCH_BASELINE)
    data = add_default!(load_batch(snapshot), baseline)
    mkpath(output)
    for (field, label, name) in (
        (:seconds, "Execution time per fold (s)", "01_execution_time"),
        (:programs, "Programs enumerated per fold", "02_program_enumerations"),
    )
        figure = performance(data, BATCH_SERIES, field, label; show_bounds,
            series_label=batch_label, legend_title="Method / batch cap / split")
        add_property_references!(figure, data)
        save_figure(figure, output, name)
    end
    save_figure(batch_enumerations(data), output, "03_property_enumerations")
    save_figure(batch_timing(data), output, "04_phase_timing")
    save_figure(batch_properties(data), output, "05_properties_used")
    save_shared_comparisons(data, output)
end

if abspath(PROGRAM_FILE) == @__FILE__
    paths = filter(!=("--bounds"), ARGS)
    length(paths) <= 2 || error("Usage: plot_phalcon_batch.jl [snapshot_dir] [output_dir] [--bounds]")
    plot_batch(paths...; show_bounds="--bounds" in ARGS)
end
