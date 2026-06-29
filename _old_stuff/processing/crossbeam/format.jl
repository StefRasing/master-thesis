using JSON3

files = ["processing/crossbeam/run_$n.json" for n in 1:5]

merged = Vector{Dict{String, Any}}()

for file in files
    data = JSON3.read(open(file))

    for r in data.results
        push!(merged, Dict(
            "execution_time" => r.elapsed_time,
            "programs_enumerated" => r.num_values_explored,
            "solved" => r.success,
            "problem_name" => r.task,
            # optionally add:
            # "solution_weight" => r.solution_weight,
            # "num_unique_values" => r.num_unique_values,
            # "file" => file
        ))
    end
end

open("processing/crossbeam/crossbeam_strings.json", "w") do io
    JSON3.pretty(io, merged)
end