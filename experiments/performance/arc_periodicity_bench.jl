# Compare the current production periodicity primitives with their previous implementations.
using HerbBenchmarks, Random, Statistics
const ARC = HerbBenchmarks.ARC_AGI1
const sink = Ref(0)
# Reference implementation retained for a repeatable before/after comparison.
function previous_period(object, axis)
    normalized = ARC.normalize_zero_indexed(object)
    extent = axis == 1 ? ARC.height(normalized) : ARC.width(normalized)
    for p in 1:extent-1
        offset = axis == 1 ? CartesianIndex(-p, 0) : CartesianIndex(0, -p)
        shifted = ARC.shift(normalized, offset)
        pruned = Set((color, index) for (color, index) in shifted if index[axis] >= 0)
        issubset(pruned, normalized) && return p
    end
    return extent
end
function measure(label,f;n=200)
    for _ in 1:10; sink[]=f(); end
    ss=[@timed(for _ in 1:n; sink[]=f(); end) for _ in 1:5]
    println(label,": ", round(median(s.time for s in ss)/n*1e6;digits=2)," us, ",median(s.bytes for s in ss)/n," bytes")
end
function main()
    rng=Xoshiro(42)
    # Check duplicates, negative coordinates, empties, and random sparse objects.
    for _ in 1:100
        object=[(rand(rng,0:9),CartesianIndex(rand(rng,-5:5),rand(rng,-5:5))) for _ in 1:rand(rng,0:50)]
        @assert ARC.hperiod(object)==previous_period(object,2)
        @assert ARC.vperiod(object)==previous_period(object,1)
    end
    for (label,grid) in (("task5 input", ARC.problem_045e512c.spec[1].in[:_arg_1]),
                          ("random 30x30",rand(rng,0:9,30,30)))
        object=ARC.asobject(grid)
        println(label," dimensions=",size(grid))
        for (name,baseline,axis) in (("hperiod",ARC.hperiod,2),("vperiod",ARC.vperiod,1))
            @assert baseline(object)==previous_period(object,axis)
            measure(name*" previous",()->previous_period(object,axis))
            measure(name*" current",()->baseline(object))
        end
    end
end
main()
