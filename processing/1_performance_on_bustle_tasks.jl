using JSON3
using Plots
using Statistics
using HerbBenchmarks

struct Result
    problem_name::String
    solved::Bool
    execution_time::Float64
    programs_enumerated::Int64
end

function step_align(best_x, best_y, worst_x, worst_y)
    x = sort(unique(vcat(best_x, worst_x)))

    function step_values(xs, ys, xgrid)
        result = similar(xgrid, eltype(ys))
        j = 1
        current = ys[1]

        for (i, x) in enumerate(xgrid)
            while j < length(xs) && xs[j + 1] <= x
                j += 1
                current = ys[j]
            end
            result[i] = current
        end

        result
    end

    return x, step_values(best_x, best_y, x), step_values(worst_x, worst_y, x)
end

function aggregate_best_worst(results, field::Symbol)
    grouped = Dict{String, Vector{Result}}()

    for r in results
        push!(get!(grouped, r.problem_name, Result[]), r)
    end

    best = Float64[]
    worst = Float64[]

    for (_, rs) in grouped
        solved_rs = filter(r -> r.solved, rs)
        unsolved_rs = filter(r -> !r.solved, rs)
        vals_solved = getfield.(solved_rs, field)

        # Best: minimum of solved if any solved§
        if !isempty(solved_rs)
            push!(best, minimum(vals_solved))
        end

        # Worst: maximum of solved if no unsolved
        if isempty(unsolved_rs)
            push!(worst, maximum(vals_solved))
        end
    end

    return best, worst
end

function load_results(file)
    data = JSON3.read(read(file, String))

    if occursin("crossbeam", file)
        return [
            Result(
                x.problem_name,
                x.solved,
                x.execution_time,
                x.programs_enumerated
            )
            for x in data
        ]
    end

    benchmark = HerbBenchmarks.PBE_SLIA_Track_2019
    task_names = [String(s)[9:end] for s in names(benchmark; all=true) if startswith(String(s), "problem_") && all(f -> !occursin(f, String(s)), ["short", "long", "repeat", "small"])]
    problems = [getfield(benchmark, Symbol("problem_", name)) for name in task_names]
    grammars = [getfield(benchmark, Symbol("grammar_", name)) for name in task_names]
    tasks = [p.name for (p, g) in zip(problems, grammars) if g.rules[1] == :ntString && all(t == :ntString for (t,r) in zip(g.types, g.rules) if r isa Symbol && occursin("_arg_", string(r)))]

    return [
        Result(
            x.problem_name,
            x.solved,
            x.execution_time,
            x.programs_enumerated
        )
        for x in data if x.problem_name in tasks
    ]
end

function cumulative_curve(results, field::Symbol, max, min)
    sorted = sort(results, by = r -> getfield(r, field))

    costs = [getfield(r, field) for r in sorted]
    solved = Int.(getfield.(sorted, :solved))

    cumulative_solved = cumsum(solved)

    percent_solved = cumulative_solved ./ 5

    mask = costs .> 0
    costs = costs[mask]
    percent_solved = percent_solved[mask]

    pushfirst!(costs, min)
    pushfirst!(percent_solved, percent_solved[begin])

    push!(costs, max)
    push!(percent_solved, percent_solved[end])

    return costs, percent_solved
end

function cumulative_from_costs(costs::Vector{Float64}, max, min)
    sorted = sort(costs)
    solved = collect(1:length(sorted))

    pushfirst!(sorted, min)
    pushfirst!(solved, solved[begin])

    push!(sorted, max)
    push!(solved, solved[end])

    return sorted, solved
end

function best_worst_curve(results, field::Symbol, max_x, min_x)
    best_costs, worst_costs = aggregate_best_worst(results, field)

    # best-case ordering (optimistic)
    x_best, y_best = cumulative_from_costs(best_costs, max_x, min_x)

    # worst-case ordering (pessimistic)
    x_worst, y_worst = cumulative_from_costs(worst_costs, max_x, min_x)

    return (x_best, y_best), (x_worst, y_worst)
end

function make_plots(files, field, plot_kwargs, series_kwargs)
    global_min = Inf
    global_max = -Inf
    result_sizes = []

    for file in files
        r = load_results(file)
        global_min = min(global_min, minimum(getfield.(r, field)))
        global_max = max(global_max, maximum(getfield.(r, field)))
        push!(result_sizes, length(r))
    end

    x_plot_max = maximum(first(plot_kwargs.xticks))
    x_plot_min = minimum(first(plot_kwargs.xticks))

    @show result_sizes
    !allequal(result_sizes) && @warn "Result files contain unequal amount of problems: $(result_sizes)"
    x_plot_max < global_max && @warn "Global max $global_max falls out of xticks"
    x_plot_min > global_min && @warn "Global min $global_min falls out of xticks"

    problems = 90

    p = plot(;
        xlabel = field == :execution_time ? "Execution time (sec)" : "Programs evaluated",
        ylabel = "Problems solved (out of $problems)",
        xlims = (x_plot_min, x_plot_max),
        legend = :outerbottom,

        # Typography (all text sizes)
        guidefont = font(10),
        tickfont  = font(9),
        legendfont = font(9),

        grid = true,
        gridalpha = 0.25,
        gridcolor = :gray,
        plot_kwargs...,
    )

    hline!([problems], linestyle = :dash, color = :gray, label = "")
    annotate!(
        x_plot_max * 1.5,  # slightly to the right
        problems,
        text("$problems", 9)
    )

    for (i, file) in enumerate(files)
        results = load_results(file)

        x, y = cumulative_curve(results, field, x_plot_max, x_plot_min)

        plot!(
            p, 
            x, 
            y; 
            lw = 2, 
            fillrange=y,
            fillalpha=0.2,
            series_kwargs[i]...
        )

        annotate!(
            x_plot_max * 1.5,  # slightly to the right
            y[end] + [0, 2, -2][i],
            text(string(Int64(round(y[end]))), 9, series_kwargs[i].color)
        )

        (best_x, best_y), (worst_x, worst_y) = best_worst_curve(results, field, x_plot_max, x_plot_min)
        bw_x, best_y, worst_y = step_align(best_x, best_y, worst_x, worst_y)

        plot!(
            p,
            bw_x, 
            best_y,
            fillrange=worst_y,
            fillalpha=0.2,
            color=series_kwargs[i].color,
            linealpha=0.0,
            label=false,
        )

        @show series_kwargs[i].label, y[end]
    end

    if field == :programs_enumerated && occursin("strings", files[1]) 
        enums = [1, 700, 4100, 11000, 31000, 250000, 9000000]
        solved = [0, 10, 20, 30, 40, 70, 80]

        plot!(
            p,
            enums, solved,
            xscale = :log10,
            marker = :circle,
            label = "Bustle",
            color = RGB(0.50, 0.35, 0.70)
        )

        annotate!(
            x_plot_max * 1.5,  # slightly to the right
            77,
            text("80", 9, RGB(0.50, 0.35, 0.70))
        )
    end

    display(p)
end

gr()
default(fontfamily="Computer Modern")


function strings_bustle_tasks_time_vs_acc()
    plot_kwargs = (
        xticks = (r = -2:4; ([10.0^n for n in r], ["10e$n" for n in r])),
        xscale = :log10,
        yticks = 0:20:80,
        right_margin = 10Plots.mm,
        title = "Execution time for SyGuS strings (Bustle tasks)",
    )
    series_kwargs = [
        (label = "Phalcon", color = RGB(0.00, 0.45, 0.70)),
        (label = "Genetic Search (Levenshtein)", color = RGB(0.84, 0.37, 0.00)),
        (label = "CrossBeam", color = RGB(0.10, 0.65, 0.15)),
    ]
    names = [
        "phalcon_strings", 
        "heuristic_strings",
        "crossbeam_strings",
    ]
    files = ["data/$(name).json" for name in names]
    make_plots(files, :execution_time, plot_kwargs, series_kwargs)
    savefig("plots/strings_bustle_tasks_time_vs_acc.png")
end

#=
    SyGuS string benchmark matched with Absynth
    Enum vs Accuracy
=#
function strings_bustle_tasks_enum_vs_acc()
    plot_kwargs = (
        xticks = (r = 2:7; ([10.0^n for n in r], ["10e$n" for n in r])),
        xscale = :log10,
        yticks = 0:20:80,
        right_margin = 10Plots.mm,
        title = "Program evaluations for SyGuS strings (Bustle tasks)",
    )
    series_kwargs = [
        (label = "Phalcon", color = RGB(0.00, 0.45, 0.70)),
        (label = "Genetic Search (Levenshtein)", color = RGB(0.84, 0.37, 0.00)),
        (label = "CrossBeam", color = RGB(0.10, 0.65, 0.15)),
    ]
    names = [
        "phalcon_strings", 
        "heuristic_strings",
        "crossbeam_strings",
    ]
    files = ["data/$(name).json" for name in names]
    make_plots(files, :programs_enumerated, plot_kwargs, series_kwargs)
    savefig("plots/strings_bustle_tasks_enum_vs_acc.png")
end

strings_bustle_tasks_time_vs_acc()
strings_bustle_tasks_enum_vs_acc()
