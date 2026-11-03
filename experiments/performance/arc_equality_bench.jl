# julia --project=. experiments/performance/arc_equality_bench.jl
using HerbBenchmarks, Random, Statistics
const ARC = HerbBenchmarks.ARC_AGI1
const sink = Ref(false)
function measure(label, f; n=2000)
    for _ in 1:20; sink[] = f(); end
    samples = [@timed(for _ in 1:n; sink[] = f(); end) for _ in 1:5]
    println(label, ": ", round(median(x.time for x in samples)/n*1e6; digits=3),
        " us, ", median(x.bytes for x in samples)/n, " bytes")
end
function main()
    rng = Xoshiro(42)
    for size in (25,100,900)
        a = ARC.asobject(rand(rng,0:9,1,size))
        b = shuffle(rng,a)
        unequal = copy(b); unequal[1] = (mod(unequal[1][1]+1,10),unequal[1][2])
        cached_a,cached_b,cached_unequal = Set(a),Set(b),Set(unequal)
        println("cells=",size)
        measure("Set equality, identical reference", ()->a==a)
        measure("identity guard, identical reference", ()->a===a || a==a)
        measure("Set equality, reordered equal", ()->a==b)
        measure("cached Sets, reordered equal", ()->cached_a==cached_b)
        measure("Set equality, unequal", ()->a==unequal)
        measure("cached Sets, unequal", ()->cached_a==cached_unequal)
        @assert (a==b) == (cached_a==cached_b)
        @assert (a==unequal) == (cached_a==cached_unequal)
        # Reordered equal Objects currently hash differently: any replacement cache
        # must define hashing and equality together, not merely sort for comparison.
        println("equal Object hashes match: ",hash(a)==hash(b))
    end
end
main()
