using JSON3
using Plots
using Polynomials
using Colors
using Statistics

struct Result
    program_synthesis_durations::Vector{Float64}
    property_invention_durations::Vector{Float64}
end

# Average duration per iteration
function average_per_iteration(xs, ys)
    iterations = sort(unique(xs))
    averages = [
        mean(ys[xs .== i])
        for i in iterations
    ]
    return iterations, averages
end


# Load the JSON array
i = 2
path = ["data/timing/phalcon_strings6.json", "data/timing/phalcon_bitvectors6.json", "data/timing/phalcon_arc_6a.json"][i]
results = JSON3.read(read(path, String), Vector{Result})

# Collect points
syn_x = Int[]
syn_y = Float64[]
inv_x = Int[]
inv_y = Float64[]

for r in results
    append!(syn_x, eachindex(r.program_synthesis_durations))
    append!(syn_y, r.program_synthesis_durations)

    append!(inv_x, eachindex(r.property_invention_durations))
    append!(inv_y, r.property_invention_durations)
end

ylims = [(0,20),(0,100),(0,400)][i]
xlims = [(0,20),(0,20),(0,15)][i]

# Remove outliers only for plotting/trend calculation
ymax = ylims[2]

syn_mask = syn_y .<= ymax
inv_mask = inv_y .<= ymax

syn_x_filtered = syn_x[syn_mask]
syn_y_filtered = syn_y[syn_mask]

inv_x_filtered = inv_x[inv_mask]
inv_y_filtered = inv_y[inv_mask]

# Average per iteration
syn_avg_x, syn_avg_y = average_per_iteration(syn_x_filtered, syn_y_filtered)
inv_avg_x, inv_avg_y = average_per_iteration(inv_x_filtered, inv_y_filtered)

# Trend lines through averages
syn_fit = fit(syn_avg_x, syn_avg_y, 1)
inv_fit = fit(inv_avg_x, inv_avg_y, 1)

synthesis_color = RGB(0.00, 0.45, 0.70)
invention_color = RGB(0.84, 0.37, 0.00)

p1 = scatter(
    syn_x_filtered,
    syn_y_filtered;
    color = synthesis_color,
    markerstrokewidth = 0,
    markersize = 4,
    markeralpha = 0.15,
    label = "All runs",
    title = "Program synthesis",
    xlabel = "Iteration",
    ylabel = "Duration (s)",
    ylims = ylims,
    xlims = xlims,
)

# Average dots
scatter!(
    p1,
    syn_avg_x,
    syn_avg_y;
    color = synthesis_color,
    marker = :circle,
    markersize = 6,
    markeralpha = 0.75,
    markerstrokewidth = 0,
    label = "Average",
)

# Trend line (strongest)
xs = range(minimum(syn_avg_x), maximum(syn_avg_x), length=200)
plot!(
    p1,
    xs,
    syn_fit.(xs);
    color = synthesis_color,
    lw = 2,
    label = "Trend",
)


p2 = scatter(
    inv_x_filtered,
    inv_y_filtered;
    color = invention_color,
    markerstrokewidth = 0,
    markersize = 4,
    markeralpha = 0.15,
    label = "All runs",
    title = "Property invention",
    xlabel = "Iteration",
    ylims = ylims,
    xlims = xlims,
)

scatter!(
    p2,
    inv_avg_x,
    inv_avg_y;
    color = invention_color,
    marker = :circle,
    markersize = 6,
    markeralpha = 0.75,
    markerstrokewidth = 0,
    label = "Average",
)

xs = range(minimum(inv_avg_x), maximum(inv_avg_x), length=200)
plot!(
    p2,
    xs,
    inv_fit.(xs);
    color = invention_color,
    lw = 2,
    label = "Trend",
)

domain_pretty = ["SyGuS strings", "SyGuS bitvectors", "ARC"][i]

plot(
    p1,
    p2,
    layout = (1, 2),
    size = (1200,600),
    left_margin = 10Plots.mm,
    right_margin = 5Plots.mm,
    bottom_margin = 5Plots.mm,
    top_margin = 5Plots.mm,
    titlefontsize = 11,
    plot_titlefontsize = 13,
    plot_title = "Runtime per iteration for $domain_pretty",
)

domain = ["strings", "bitvectors", "arc"][i]
savefig("plots/time_composition_$domain.png")


# p = scatter(
#     syn_x_filtered,
#     syn_y_filtered;
#     color = synthesis_color,
#     markerstrokewidth = 0,
#     markersize = 4,
#     markeralpha = 0.0,
#     label = false,
#     xlabel = "Iterations →",
#     ylabel = "Time (sec) →",
#     xticks = ([0, xlims[2]], ["0", string(xlims[2])]),
#     yticks = ([0, ylims[2]], ["0", string(ylims[2])]),
#     tickfontsize = 18,
#     legend = false,
#     guidefontsize = 20,
#     title = "",
#     ylims = ylims,
#     xlims = xlims,
#     size = (600, 600),
#     left_margin = 10Plots.mm,
#     right_margin = 5Plots.mm,
#     bottom_margin = 8Plots.mm,
#     top_margin = 5Plots.mm,
# )

# scatter!(
#     p,
#     inv_x_filtered,
#     inv_y_filtered;
#     color = invention_color,
#     markerstrokewidth = 0,
#     markersize = 4,
#     markeralpha = 0.0,
#     label = false,
# )

# # Average dots
# scatter!(
#     p,
#     syn_avg_x,
#     syn_avg_y;
#     color = synthesis_color,
#     marker = :circle,
#     markersize = 6,
#     markeralpha = 0.75,
#     markerstrokewidth = 0,
#     label = false,
# )

# scatter!(
#     p,
#     inv_avg_x,
#     inv_avg_y;
#     color = invention_color,
#     marker = :circle,
#     markersize = 6,
#     markeralpha = 0.75,
#     markerstrokewidth = 0,
#     label = false,
# )

# # Trend lines
# syn_trend_x = range(
#     minimum(syn_avg_x),
#     maximum(syn_avg_x);
#     length = 200,
# )
# plot!(
#     p,
#     syn_trend_x,
#     syn_fit.(syn_trend_x);
#     color = synthesis_color,
#     lw = 2,
#     label = false,
# )

# inv_trend_x = range(
#     minimum(inv_avg_x),
#     maximum(inv_avg_x);
#     length = 200,
# )
# plot!(
#     p,
#     inv_trend_x,
#     inv_fit.(inv_trend_x);
#     color = invention_color,
#     lw = 2,
#     label = false,
# )

# domain = ["strings", "bitvectors", "arc"][i]
# savefig(p, "plots/time_composition_$domain.png")