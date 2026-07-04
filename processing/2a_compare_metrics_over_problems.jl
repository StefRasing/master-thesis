using JSON3
using Statistics
using Plots

function average_iterations(folder)
    files = sort(filter(f -> endswith(f, ".json"),
                        readdir(folder; join=true)))

    # problem_name => iteration counts from all runs
    iterations = Dict{String, Vector{Int}}()

    for file in files
        data = JSON3.read(read(file, String))

        for obj in data
            !obj.solved && continue

            # iters = length(obj.population_costs)
            # iters = obj.programs_enumerated
            # iters = round(obj.execution_time)
            # iters = length(obj.heuristic) + length(get(obj, :library_properties, []))
            # iters = length(obj.heuristic)
            iters = length(obj.solution)
            push!(get!(iterations, String(obj.problem_name), Int[]), iters)
        end
    end

    Dict(name => mean(vals) for (name, vals) in iterations)
end

# avg1 = average_iterations("data/phalcon_strings")
# avg2 = average_iterations("data/transferable_phalcon_strings")
avg1 = average_iterations("data/phalcon_bitvectors")
avg2 = average_iterations("data/transferable_phalcon_bitvectors")
# avg1 = average_iterations("data/phalcon_arc")
# avg2 = average_iterations("data/transferable_phalcon_arc")

# Compare only problems that appear in both folders
problems = sort(collect(intersect(keys(avg1), keys(avg2))))
perm = sortperm([avg1[p] for p in problems])
problems = problems[perm]

scatter(
    # [n for n in 1:length(problems)],
    # sort([avg1[p] for p in problems]);
    problems,
    [avg1[p] for p in problems];
    label="Phalcon",
    lw=2,
    marker=:circle,
    xlabel="Problem",
    ylabel="Average iterations",
    xrotation=90,
    size=(1200, 500),
    color=:blue,
)

scatter!(
    # [n for n in 1:length(problems)],
    # sort([avg2[p] for p in problems]);
    problems,
    [avg2[p] for p in problems];
    label="Transferable Phalcon",
    lw=2,
    marker=:square,
    color=:red,
)

vals1 = [avg1[p] for p in problems]
vals2 = [avg2[p] for p in problems]

mean1 = mean(vals1)
mean2 = mean(vals2)

@show mean1
@show mean2

hline!(
    [mean1];
    label="Phalcon mean",
    linestyle=:dash,
    linewidth=2,
    color=:blue,
)

hline!(
    [mean2];
    label="Transferable Phalcon mean",
    linestyle=:dash,
    linewidth=2,
    color=:red,
)