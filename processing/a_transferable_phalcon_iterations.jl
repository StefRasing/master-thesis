using JSON3
using GLM
using DataFrames
using Plots
using Statistics

function moving_average(x, w=5)
    [mean(@view x[max(1,i-w+1):i]) for i in eachindex(x)]
end

# files = ["data/transferable_phalcon_strings/transferable_phalcon_strings$(n).json"
#          for n in 1:5]
files = ["data/transferable_phalcon_strings/transferable_phalcon_strings_test.json"]

results = Dict()

for file in files
    data = JSON3.read(read(file, String))
    results[file] = [length(task.population_costs) for task in data if task.solved]
end

p = plot(
    xlabel = "Task",
    ylabel = "Iterations",
    legend = false,
)

for (_, iterations) in results
    n = 1
    smoothed = moving_average(iterations, n)
    x = 1:length(smoothed)

    # smoothed curve
    plot!(
        p,
        x[n:end],
        smoothed[n:end],
        linewidth = 2,
        alpha = 0.4,
    )

    # linear trend line through smoothed data
    df = DataFrame(x=x, y=smoothed)
    model = lm(@formula(y ~ x), df)

    trend = predict(model)

    plot!(
        p,
        x,
        trend,
        linewidth = 3,
    )
end

display(p)