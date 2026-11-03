# Run from the thesis project: julia --project=. experiments/performance/arc_primitives.jl
# Synthetic microbenchmarks; timings are not end-to-end search speedups.
using Statistics, Random
module ARC
include(get(ENV, "ARC_PRIMITIVES", normpath(joinpath(@__DIR__, "..", "..", "..", "HerbBenchmarks.jl", "src", "data", "ARC_AGI1", "arc_primitives.jl"))))
end
const sink = Ref{Any}()
function measure(label, f; n=2000)
    for _ in 1:10; f(); end
    samples = [@timed(for _ in 1:n; sink[] = f(); end) for _ in 1:5]
    t = median(s.time for s in samples) / n * 1e6
    b = median(s.bytes for s in samples) / n
    println(label, ": ", round(t;digits=3), " us, ", round(b;digits=1), " bytes")
end
# Previous implementations retained for before/after measurement.
old_asindices(grid) = vcat(collect(CartesianIndices(grid))...)
old_asobject(grid) = [(grid[idx], idx) for idx in vec(old_asindices(grid))]
old_hupscale(grid, factor) = reduce(vcat, [permutedims(repeat(row, inner=(factor,))) for row in eachrow(grid)])
old_vupscale(grid, factor) = reduce(hcat, [repeat(col, inner=(factor,)) for col in eachcol(grid)])
old_manhattan(a, b) = minimum(abs(ai[1] - bi[1]) + abs(ai[2] - bi[2]) for ai in ARC.toindices(a), bi in ARC.toindices(b))
Random.seed!(42)
const g = rand(0:9,30,30); const small = g[1:10,1:10]; const u = UInt8.(g)
const a = ARC.asobject(g); const b = ARC.shift(a, CartesianIndex(2,3))
@assert ARC.hupscale(small,3) == repeat(small;inner=(1,3))
@assert ARC.vupscale(small,3) == repeat(small;inner=(3,1))
@assert isequal(ARC.asobject(g), old_asobject(g))
@assert isequal(ARC.asindices(g), vec(collect(CartesianIndices(g))))
@assert ARC.manhattan(a,b) == old_manhattan(a,b)
println("Julia ", VERSION)
for (label,f) in [
("hupscale previous", ()->old_hupscale(small,3)),
("hupscale current", ()->ARC.hupscale(small,3)),
("vupscale previous", ()->old_vupscale(small,3)),
("vupscale current", ()->ARC.vupscale(small,3)),
("asobject current", ()->ARC.asobject(g)),
("asobject previous", ()->old_asobject(g)),
("manhattan current", ()->ARC.manhattan(a,b)),
("manhattan previous", ()->old_manhattan(a,b)),
("copy Int64", ()->copy(g)), ("copy UInt8", ()->copy(u)),
("mirror Int64", ()->reverse(g;dims=2)), ("mirror UInt8", ()->reverse(u;dims=2)),
("count Int64", ()->count(==(3),g)), ("count UInt8", ()->count(==(3),u)),
("hash Int64", ()->hash(g)), ("hash UInt8", ()->hash(u)),
("objects", ()->ARC.objects(g,true,false,true)),
("asindices previous", ()->old_asindices(g)),
("asindices current", ()->ARC.asindices(g)),
("frontiers", ()->ARC.frontiers(g))]
    measure(label,f; n=occursin("manhattan",label) ? 50 : 2000)
end
println("grid payload: ", sizeof(g), " vs ", sizeof(u))
