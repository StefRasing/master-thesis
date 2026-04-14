using Query, StatsPlots, DataFrames, LsqFit

function time_over_solution_size(datas::Vector{DataFrame}; label=r->r.iterator, kwargs...)
    time_over_solution_size(vcat(datas...); label=label, kwargs...)
end

function time_over_solution_size(data::DataFrame; label=r->r.iterator, kwargs...)
    # Ensure that dataframe has column "results"
    @assert "results" in names(data)

    [transform!(row.results, [:solution] => ByRow(s -> ismissing(s) ? missing : length(s)) => :solution_size) for row in eachrow(data)]

    # Find the longest execution time for any solved problem to scale the graph
    longest_program = maximum(
        maximum(df.solution_size[df.solved])
        for df in data.results
        if any(df.solved)
    )

    # Init empty plot
    p = scatter(;
        xlabel = "Solution size",
        ylabel = "Execution time (s)",
        xlims = (0, longest_program * 1.1),
        kwargs...,
    )

    for row in eachrow(data)
        # Assert that each results dataframe has columns "solved" and "execution_time_sec"
        @assert "solved" in names(row.results)
        @assert "execution_time_sec" in names(row.results)

        # Data process pipeline:
        filtered = row.results |>
            # Only keep solved programs
            @filter(_.solved) |>

            # Remove outlier
            @filter(_.execution_time_sec < 200) |>

            # Sort on execution time
            @orderby(_.solution_size) |>

            # Collect results
            DataFrame

        # Add to plot
        @df filtered scatter!(p,
            :solution_size, 
            :execution_time_sec, 
            label=label(row),
        )

        x = Vector{Int64}(filtered.solution_size)
        y = filtered.execution_time_sec
        power_law(x, p) = p[1] .* x .^ p[2]
        p0 = [1.0, 1.0]
        fit = curve_fit(power_law, x, y, p0)
        a, b = fit.param
        x_range = range(0, longest_program, length=100)
        plot!(x_range, power_law(x_range, [a, b]), label="trend", color=p.series_list[end][:seriescolor])
    end

    # Return plot
    return p
end