using Query, StatsPlots, DataFrames

function problems_solved_over_number_of_properties(datas::Vector{DataFrame}; label=r->r.iterator, kwargs...)
    problems_solved_over_number_of_properties(vcat(datas...); label=label, kwargs...)
end

function problems_solved_over_number_of_properties(data::DataFrame; label=r->r.iterator, kwargs...)
    # Ensure that dataframe has column "results"
    @assert "results" in names(data)

    [transform!(row.results, [:heuristic] => ByRow(h -> length(Dict(h)[:selected_properties])) => :number_of_properties) for row in eachrow(data)]

    # Find the maximum amount of enumerations for any solved problem to scale the graph
    max_properties = maximum(
        maximum(df.number_of_properties[df.solved])
        for df in data.results
        if any(df.solved)
    )

    # Init empty plot
    p = plot(;
        xlabel = "Number of properties",
        ylabel = "Problems solved",
        xlims = (0, max_properties * 1.1),
        # yformatter = y -> string(Int(round(y * 100)), "%"),
        kwargs...
    )

    for row in eachrow(data)
        # Assert that each results dataframe has columns "solved" and "execution_time_sec"
        @assert "solved" in names(row.results)
        @assert "number_of_properties" in names(row.results)

        # Data process pipeline:
        row.results |>
            # Sort on execution time
            @orderby(_.number_of_properties) |>

            # Take the cummulative sum 
            DataFrame |>
                (df -> DataFrame(
                    cumulative_solved = [0; cumsum(df.solved)...; maximum(cumsum(df.solved))],
                    number_of_properties = [0; df.number_of_properties...; max_properties * 1.1]
                )) |>

            # Add to plot
            @df plot!(p,
                :number_of_properties, 
                :cumulative_solved, 
                seriestype = :steppost,
                label=label(row),
            )
    end

    # Return plot
    return p
end