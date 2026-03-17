using JSON, Plots

function exe(name, datafiles)
    plot()
    number_of_problemss = []

    x_ticks = [10^1, 10^2, 10^3, 10^4, 10^5, 10^6]
    xticks!(x_ticks)

    for datafile in datafiles
        filename = "data/$datafile.json"
        data = isfile(filename) ? JSON.parsefile(filename) : Any[]

        number_of_problems = length(data)
        push!(number_of_problemss, number_of_problems)
        pool_size = first(data)["hyperparameters"]["pool_size"]
        
        filter!(x -> !isnothing(x["solution"]), data)
        map!(x -> x["statistics"]["programs_evaluated"], data)
        sort!(data)

        cum = (1:length(data))# ./ number_of_problems .* 100

        plot!([x_ticks[begin]; data; x_ticks[end]], [0; cum; cum[end]],
            seriestype = :steppost,
            label = "Pool size $pool_size",
            xscale = :log10,
            legend = :topleft,
            )
    end

    @assert allequal(number_of_problemss)

    title!("Problems solved vs program evaluations")
    xlabel!("Programs evaluated")
    ylabel!("Problems solved (out of $(number_of_problemss[1]))")

    savefig("results/plots/$name.png")
end

exe("programs_evaluated_vs_solved_problems_SyGuS_strings", [
    "SyGuS strings-2026-03-17_13:47:57-pool_size=1",
    "SyGuS strings-2026-03-17_13:25:56-pool_size=5",
    "SyGuS strings-2026-03-17_13:53:04-pool_size=10",
])