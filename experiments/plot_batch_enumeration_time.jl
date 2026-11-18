# julia --project=. experiments/plot_batch_enumeration_time.jl [snapshot_dir] [output_dir]
# Dots average execution_time / programs_enumerated over eligible repetitions
# for each problem-fold. Mean markers give each dot equal weight. Only runs selecting
# exactly the requested property count are included. Total time includes invention.
include("plot_phalcon_batch.jl")
using Statistics: mean

function plot_batch_enumeration_time(snapshot=BATCH_ROOT, output=joinpath(snapshot, "plots"))
    data = load_batch(snapshot)
    mkpath(output)
    panels = Plots.Plot[]
    fits = NamedTuple[]
    open(joinpath(output, "06_time_per_enumeration.tsv"), "w") do io
        println(io, "domain\tproperties\tincluded_fold_runs\texcluded_fold_runs\tproblem_folds\tmean_microseconds_per_program")
        for (domain, title) in DOMAINS
            ax = panel(title; xlabel="Selected properties",
                ylabel="Execution time per program (μs)", xticks=collect(BATCH_CAPS),
                xscale=:identity, yscale=:identity, xlims=(0, 45), legend=:topleft)
            means = Float64[]
            peak = 0.0
            for cap in BATCH_CAPS
                groups = data[domain, cap]
                ratios = Dict{Tuple{String,Int},Vector{Float64}}()
                total = 0
                included = 0
                for ((_, problem), folds) in groups, (fold, r) in folds
                    total += 1
                    if length(r.agreements) == cap && r.programs > 0
                        push!(get!(ratios, (problem, fold), Float64[]), 1e6 * r.seconds / r.programs)
                        included += 1
                    end
                end
                isempty(ratios) && error("No observations for $domain, $cap")
                # Each dot represents one problem-fold, averaged over eligible repetitions.
                dots = [mean(ratios[key]) for key in sort!(collect(keys(ratios)))]
                value = mean(dots)
                push!(means, value)
                peak = max(peak, maximum(dots))
                scatter!(ax, fill(cap, length(dots)), dots; color="#0072B2",
                    markeralpha=0.18, markerstrokewidth=0, markersize=3,
                    label=cap == first(BATCH_CAPS) ? "Problem-fold" : false)
                println(io, join((domain, cap, included, total - included, length(dots), value), '\t'))
            end
            scatter!(ax, collect(BATCH_CAPS), means; color="#D55E00", markershape=:diamond,
                markerstrokecolor=:white, markerstrokewidth=1, markersize=7, label="Mean")
            # Equal weight per property-count mean for an ordinary least-squares fit.
            counts = Float64.(collect(BATCH_CAPS))
            slope = sum((counts .- mean(counts)) .* (means .- mean(means))) /
                sum(abs2, counts .- mean(counts))
            intercept = mean(means) - slope * mean(counts)
            predicted = intercept .+ slope .* counts
            r_squared = 1 - sum(abs2, means .- predicted) / sum(abs2, means .- mean(means))
            push!(fits, (; domain, intercept, slope, r_squared))
            formula = "t(p) = $(round(intercept; digits=2)) + $(round(slope; digits=2))p μs"
            plot!(ax, [0, 40], intercept .+ slope .* [0, 40]; color="#222222",
                linewidth=2, label=formula)
            plot!(ax; ylims=(0, 1.08peak))
            push!(panels, ax)
        end
    end
    open(joinpath(output, "06_time_per_enumeration_fit.tsv"), "w") do io
        println(io, "domain\tbase_microseconds_per_program\tadditional_microseconds_per_property\tr_squared")
        for fit in fits
            println(io, join((fit.domain, fit.intercept, fit.slope, fit.r_squared), '\t'))
            println("$(fit.domain): base $(fit.intercept) μs, per property $(fit.slope) μs, R²=$(fit.r_squared)")
        end
    end
    figure = plot(panels...; layout=(1, 2), size=(1000, 420))
    save_figure(figure, output, "06_time_per_enumeration")
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) <= 2 || error("Usage: plot_batch_enumeration_time.jl [snapshot_dir] [output_dir]")
    plot_batch_enumeration_time(ARGS...)
end
