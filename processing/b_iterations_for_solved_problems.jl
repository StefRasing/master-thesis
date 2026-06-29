using JSON3
using Plots

objs = JSON3.read(read("data/phalcon_arc.json", String))

lengths = [
    length(obj.heuristic)
    for obj in objs
    if obj.solved
]

histogram(
    lengths;
    bins = :auto,
    xlabel = "Heuristic length",
    ylabel = "Count",
    title = "Heuristic lengths for solved tasks (arc)",
    legend = false,
)

savefig("plots/heuristic_length_arc.png")