function append_result(path, result)
    results = if isfile(path)
        JSON3.read(read(path, String), Vector{Any})
    else
        Any[]
    end

    push!(results, result)

    open(path, "w") do io
        JSON3.pretty(io, results)
    end
end

function performed_repetitions(path, problem_name)
    !isfile(path) && return 0

    results = JSON3.read(read(path, String), Vector{Any})
    return count(result["problem_name"] == problem_name for result in results)
end
