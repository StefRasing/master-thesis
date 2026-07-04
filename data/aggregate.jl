using JSON3

# name = "heuristic_arc"
# name = "phalcon_bitvectors"
# name = "phalcon_strings"
# name = "phalcon_arc"
# name = "transferable_phalcon_strings"
# name = "transferable_phalcon_bitvectors"
name = "transferable_phalcon_arc"
# name = "strict_phalcon_strings"
# name = "strict_phalcon_bitvectors"

path = "data/$name.json"
dir = "data/$name"

# Read and merge all arrays
data = Any[]

for f in readdir(dir)
    endswith(f, ".json") || continue

    arr = JSON3.read(read(joinpath(dir, f), String))
    println("$f: $(length(arr)) tasks")

    append!(data, arr)
end

# Sort by the chosen field
sort!(data, by = x -> x["problem_name"])

# Write result
open(joinpath(path), "w") do io
    JSON3.pretty(io, data)
end