using JSON, Plots

function exe(name, datafiles)
    plot()
    number_of_problemss = []

    x_ticks = [10^-1, 10^0, 10^1, 10^2]
    xticks!(x_ticks)

    for (datafile, title) in datafiles
        filename = "data/$datafile.json"
        data = isfile(filename) ? JSON.parsefile(filename) : Any[]

        number_of_problems = length(data)
        push!(number_of_problemss, number_of_problems)
        
        filter!(x -> !isnothing(x["solution"]), data)
        map!(x -> x["statistics"]["execution_time_seconds"], data)
        sort!(data)

        cum = (1:length(data))# ./ number_of_problems .* 100


        plot!([x_ticks[begin]; data; x_ticks[end]], [0; cum; cum[end]],
            seriestype = :steppost,
            label = title,
            xscale = :log10,
            legend = :topleft,
            )
    end

    @assert allequal(number_of_problemss)

    title!("Problems solved over time")
    xlabel!("Execution time (sec)")
    ylabel!("Problems solved (out of $(number_of_problemss[1]))")

    savefig("results/plots/$name.png")
end

exe("execution_time_vs_solved_problems_for_pool_size_SyGuS_strings", [
    ("SyGuS strings-2026-03-17_13:47:57-pool_size=1", "Pool size 1"),
    ("SyGuS strings-2026-03-17_13:25:56-pool_size=5", "Pool size 5"),
    ("SyGuS strings-2026-03-17_13:53:04-pool_size=10", "Pool size 10"),
])

exe("execution_time_vs_solved_problems_for_max_properties_SyGuS_strings", [
    ("SyGuS strings-2026-03-17_13:25:56-max_properties=5", "Max properties 5"),
    ("SyGuS strings-2026-03-17_15:02:54-max_properties=10", "Max properties 10"),
    # ("", "Max properties 5"),
])