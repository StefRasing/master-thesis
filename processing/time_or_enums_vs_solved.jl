using JSON3
using Plots

struct Result
    problem_name::String
    solved::Bool
    execution_time::Float64
    programs_enumerated::Int64
end

function load_results(file)
    data = JSON3.read(read(file, String))

    return [
        Result(
            x.problem_name,
            x.solved,
            haskey(x, "execution_time_last_iteration") ? x.execution_time_last_iteration : x.execution_time,
            haskey(x, "programs_enumerate_last_iterationd") ? x.programs_enumerate_last_iterationd : x.programs_enumerated,
        )
        for x in data
    ]
end

function cumulative_curve(results, field::Symbol, max)

    sorted = sort(results, by = r -> getfield(r, field))

    costs = [getfield(r, field) for r in sorted]
    solved = Int.(getfield.(sorted, :solved))

    cumulative_solved = cumsum(solved)

    percent_solved = cumulative_solved ./ length(results) .* 100

    mask = costs .> 0
    costs = costs[mask]
    percent_solved = percent_solved[mask]

    push!(costs, max)
    push!(percent_solved, percent_solved[end])

    return costs, percent_solved
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

    !allequal(result_sizes) && @warn "Result files contain unequal amount of problems: $(result_sizes)"
    maximum(plot_kwargs.xticks) < global_max && @warn "Global max falls out of xticks"
    minimum(plot_kwargs.xticks) > global_min && @warn "Global min falls out of xticks"

    p = plot(;
        xlabel = field == :execution_time ? "Execution time (sec)" : "Programs enumerated",
        ylabel = "% problems solved",
        xscale = :log10,
        xlims = (minimum(plot_kwargs.xticks), maximum(plot_kwargs.xticks)),
        ylims = (0, 101),
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

    for (i, file) in enumerate(files)
        results = load_results(file)

        x, y = cumulative_curve(results, field, maximum(plot_kwargs.xticks))

        plot!(p, x, y; lw = 2, series_kwargs[i]...)

        @show series_kwargs[i].label, y[end]
    end

    # -------------------------------------------------------
    # Reference line at 100%
    # -------------------------------------------------------
    hline!(p, [100],
        linestyle = :dash,
        lw = 1.5,
        color = :black,
        alpha = 0.4,
        label = nothing
    )

    display(p)
end

#=

General plot settings

=#
gr()
default(fontfamily="Computer Modern")


#=
    SyGuS string benchmark
    Time vs Accuracy
=#
function strings_time_vs_acc()
    plot_kwargs = (
        xticks = ([10.0^i for i in -3:2]),
        yticks = (0:20:100)
    )
    series_kwargs = [
        (label = "phalcon (final search)", color = RGB(0.00, 0.45, 0.74), ),
        (label = "heuristic search", color = RGB(0.85, 0.33, 0.10)),
        (label = "phalcon (final search and matched subset with heuristic search)", color = RGB(0.60, 0.80, 0.95), ),
    ]
    names = [
        "phalcon_strings", 
        "heuristic_strings",
        "phalcon_strings_only_string_outputs", 
    ]
    files = ["data/$(name).json" for name in names]
    make_plots(files, :execution_time, plot_kwargs, series_kwargs)
    savefig("plots/strings_time_vs_acc.png")
end

#=
    SyGuS string benchmark
    Time vs Accuracy
=#
function strings_enums_vs_acc()
    plot_kwargs = (
        xticks = [10.0^i for i in 0:6],
        yticks = (0:20:100)
    )
    series_kwargs = [
        (label = "phalcon (final search)", color = RGB(0.00, 0.45, 0.74), ),
        (label = "heuristic search", color = RGB(0.85, 0.33, 0.10)),
        (label = "phalcon (final search and matched subset with heuristic search)", color = RGB(0.60, 0.80, 0.95), ),
    ]
    names = [
        "phalcon_strings", 
        "heuristic_strings",
        "phalcon_strings_only_string_outputs", 
    ]
    files = ["data/$(name).json" for name in names]
    make_plots(files, :programs_enumerated, plot_kwargs, series_kwargs)
    savefig("plots/strings_enum_vs_acc.png")
end


#=
    SyGuS bitvectors benchmark
    Time vs Accuracy
=#
function bitvectors_time_vs_acc()
    plot_kwargs = (
        xticks = ([10.0^i for i in -4:2]),
        yticks = (0:20:100)
    )
    series_kwargs = [
        (label = "phalcon (final search)", color = RGB(0.00, 0.45, 0.74), ),
        (label = "heuristic search", color = RGB(0.85, 0.33, 0.10)),
    ]
    names = [
        "phalcon_bitvectors", 
        "heuristic_bitvectors",
    ]
    files = ["data/$(name).json" for name in names]
    make_plots(files, :execution_time, plot_kwargs, series_kwargs)
    savefig("plots/bitvectors_time_vs_acc.png")
end


#=
    SyGuS bitvectors benchmark
    Enumerations vs Accuracy
=#
function bitvectors_enum_vs_acc()
    plot_kwargs = (
        xticks = ([10.0^i for i in 1:6]),
        yticks = (0:20:100)
    )
    series_kwargs = [
        (label = "phalcon (final search)", color = RGB(0.00, 0.45, 0.74), ),
        (label = "heuristic search", color = RGB(0.85, 0.33, 0.10)),
    ]
    names = [
        "phalcon_bitvectors", 
        "heuristic_bitvectors",
    ]
    files = ["data/$(name).json" for name in names]
    make_plots(files, :programs_enumerated, plot_kwargs, series_kwargs)
    savefig("plots/bitvectors_enum_vs_acc.png")
end


#=
    SyGuS string benchmark matched with Bustle
    Time vs Accuracy
=#
function strings_time_vs_acc_bustle()
    plot_kwargs = (
        xticks = ([10.0^i for i in -3:2]),
        yticks = (0:20:100)
    )
    series_kwargs = [
        (label = "phalcon", color = RGB(0.00, 0.45, 0.74), ),
    ]
    names = [
        "phalcon_strings", 
        "heuristic_strings",
        "phalcon_strings_only_string_outputs", 
    ]
    files = ["data/$(name).json" for name in names]
    make_plots(files, :execution_time, plot_kwargs, series_kwargs)
    savefig("plots/strings_time_vs_acc.png")
end

strings_time_vs_acc()
# strings_enums_vs_acc()
# bitvectors_time_vs_acc()
# bitvectors_enum_vs_acc()