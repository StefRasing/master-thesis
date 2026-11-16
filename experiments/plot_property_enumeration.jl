# julia --project=. experiments/plot_property_enumeration.jl [results_dir] [output_dir]
include("plot_phalcon_ablation.jl")

const PROPERTY_RESULTS = joinpath(dirname(dirname(DEFAULT_RESULTS)), "property_enumeration_50000")
const PROPERTY_DOMAINS = (DOMAINS..., ("arc", "ARC"))
const PROPERTY_POPULATIONS = (10, 20, 40, 80)
const PROPERTY_CAP = 10_000
const PROPERTY_BUDGET = 50_000
const PROPERTY_BIN_WIDTH = 2_000

function property_searches(root, domain)
    directory = joinpath(root, "$domain.runs", "results")
    hits = Int[]
    trials = searches = 0
    for path in readdir(directory; join=true)
        endswith(path, ".json") || continue
        trials += 1
        result = JSON3.read(read(path, String)).result
        searches += length(result.heuristic)
        for property in result.heuristic
            property == "failed" && continue
            property[2] == 1 || continue
            push!(hits, property[3])
        end
    end
    return (; trials, searches, hits=sort!(hits))
end

function property_histogram(title, stats, summary)
    @assert (stats.trials, stats.searches, length(stats.hits)) ==
        (summary.trials, summary.recorded_property_searches, summary.agreement_1_searches)
    @assert count(<=(PROPERTY_CAP), stats.hits) == summary.searches_with_agreement_1_by_10000
    heading = "$title: $(length(stats.hits))/$(stats.searches) searches reached agreement 1"
    median_index = summary.agreement_1_index.median
    p90 = summary.agreement_1_index.p90
    ax = panel(heading; size=(PAPER_WIDTH, 230), ylabel="Property searches",
        xlabel="Candidates evaluated (thousands)\n$(stats.trials) trials · Median: $median_index · 90th percentile: $p90",
        xlims=(-1, 50), xticks=0:5:50, legend=:topright, bottom_margin=4mm)
    counts = zeros(Int, PROPERTY_BUDGET ÷ PROPERTY_BIN_WIDTH)
    for hit in stats.hits
        @assert 1 <= hit <= PROPERTY_BUDGET
        counts[cld(hit, PROPERTY_BIN_WIDTH)] += 1
    end
    midpoints = (PROPERTY_BIN_WIDTH / 2000):(PROPERTY_BIN_WIDTH / 1000):50
    bar!(ax, midpoints, counts; bar_width=1.9, color=first(COLORS), linecolor=:black,
        linewidth=1, label=false, ylims=(0, 1.16maximum(counts)))
    vline!(ax, [PROPERTY_CAP / 1000]; color=:black, linestyle=:dash,
        linewidth=1.1, label="10,000 cap")
    for (x, n) in zip(midpoints, counts)
        iszero(n) || annotate!(ax, x, n + max(2, 0.045maximum(counts)), text(string(n), 8, "Helvetica"))
    end
    return ax
end

function property_population_panel(root, base, domain, title; legend)
    ax = panel(title; xlabel="Candidate evaluations (1,000s)", ylabel=domain == "bitvectors" ? "" : "Reached agreement 1",
        ylims=(0, 105), yticks=0:20:100, yformatter=y -> "$(round(Int, y))%",
        xlims=(0, 50), xticks=0:10:50, legend, legend_title="Population")
    vline!(ax, [PROPERTY_CAP / 1000]; color=:black, linewidth=1, label=false)
    for (population, color, linestyle) in zip(PROPERTY_POPULATIONS, COLORS, LINE_STYLES)
        stats = population == 20 ? base : property_searches(joinpath(root, "pop-$population"), domain)
        accuracy = 100 .* (1:length(stats.hits)) ./ stats.searches
        plot!(ax, [0; stats.hits ./ 1000; PROPERTY_BUDGET / 1000], [0; accuracy; last(accuracy)];
            seriestype=:steppost, color, linestyle, linewidth=2, label=string(population))
    end
    return ax
end

function plot_property_enumeration(root=PROPERTY_RESULTS, output=root)
    summary = JSON3.read(read(joinpath(root, "summary.json"), String))
    mkpath(output)
    panels = map(PROPERTY_DOMAINS) do (domain, title)
        stats = property_searches(root, domain)
        figure = property_histogram(title, stats, summary.domains[Symbol(domain)])
        savefig(figure, joinpath(output, "$(domain)_acceptance_1_histogram.png"))
        property_population_panel(root, stats, domain, title; legend=domain == "bitvectors" ? false : :bottomright)
    end
    comparisons = plot(panels[1:2]...; layout=(1, 2), size=(PAPER_WIDTH, 216))
    arc = plot(last(panels); size=(COLUMN_WIDTH, 216))
    savefig(comparisons, joinpath(output, "population_acceptance_1.png"))
    savefig(arc, joinpath(output, "arc_population_acceptance_1.png"))
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) <= 2 || error("Usage: plot_property_enumeration.jl [results_dir] [output_dir]")
    plot_property_enumeration(ARGS...)
end
