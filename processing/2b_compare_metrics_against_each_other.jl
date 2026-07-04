using JSON3
using Plots
using Statistics

function load_points(filename)
    data = JSON3.read(read(filename, String))

    x = [obj.programs_enumerated for obj in data]
    # x = [length(obj.heuristic) + length(get(obj, :library_properties, [])) for obj in data]
    # x = [length(obj.population_costs) for obj in data]

    y = [obj.execution_time for obj in data]
    # y = [obj.programs_enumerated for obj in data]


    return x, y
end

# Load the two files
# x1, y1 = load_points("data/phalcon_strings.json")
# x2, y2 = load_points("data/transferable_phalcon_strings.json")
x1, y1 = load_points("data/phalcon_bitvectors.json")
x2, y2 = load_points("data/transferable_phalcon_bitvectors.json")
# x1, y1 = load_points("data/phalcon_arc.json")
# x2, y2 = load_points("data/transferable_phalcon_arc.json")

# Create the scatter plot
scatter(
    x1, y1;
    label="Phalcon",
    xlabel="Programs enumerated",
    ylabel="Execution time",
    markersize=2,
    # ylims = (0, 4000),
    # xlims = (0, 1.5*10^6),
)

scatter!(
    x2, y2;
    label="Transferable Phalcon",
    markersize=2,
)


function trendline(x, y)
    a = cov(x, y) / var(x)
    b = mean(y) - a * mean(x)
    xs = range(minimum(x), maximum(x), length=200)
    ys = a .* xs .+ b
    xs, ys
end

xs1, ys1 = trendline(x1, y1)
plot!(xs1, ys1; color=1, linewidth=2, label="Bitvectors trend")

xs2, ys2 = trendline(x2, y2)
plot!(xs2, ys2; color=2, linewidth=2, label="Strings trend")

savefig("trend")