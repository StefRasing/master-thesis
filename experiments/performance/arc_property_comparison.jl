# Fixed-work comparison: julia --project=. --startup-file=no experiments/performance/arc_property_comparison.jl [output.json]
# The legacy primitives and switches below exist only in this diagnostic process.
using Random, JSON3, Statistics
include("../src/Experiments.jl")
const P = Experiments.Phalcon
const ARC = Experiments.HerbBenchmarks.ARC_AGI1
const LEGACY_PERIOD = Ref(false)
function previous_period(object, axis)
    normalized = ARC.normalize_zero_indexed(object)
    extent = axis == 1 ? ARC.height(normalized) : ARC.width(normalized)
    for p in 1:extent-1
        offset = axis == 1 ? CartesianIndex(-p,0) : CartesianIndex(0,-p)
        shifted = ARC.shift(normalized,offset)
        pruned = Set((c,CartesianIndex(i)) for (c,i) in shifted if i[axis] >= 0)
        issubset(pruned,normalized) && return p
    end
    extent
end
function diagnostic_period(object, axis)
    LEGACY_PERIOD[] ? previous_period(object,axis) : ARC._object_period(ARC.normalize_zero_indexed(object),Val(axis))
end
@eval ARC begin
    hperiod(object::Object)::Integer = $diagnostic_period(object,2)
    vperiod(object::Object)::Integer = $diagnostic_period(object,1)
end
struct CandidateLimit <: Exception end
const LIMIT = 700
function main()
    adapter = Experiments.benchmark_adapter(:arc)
    problem = ARC.problem_045e512c
    train,_,_ = Experiments.split_problem(problem,[length(problem.spec)])
    println("Preparing task5 initialized population"); flush(stdout)
    config=Experiments.ExperimentConfig(benchmark=:arc,store=false)
    interpreter=Experiments.prepare_interpreter(config,adapter,problem,ARC.grammar_hodel)
    iterator=P.GeneticIterator(ARC.grammar_hodel,:Start; benchmark=ARC,problem=train,
        interpreter,rng=Xoshiro(42),cost=_ -> 0,population_size=20,
        max_extension_size=1,max_initial_population_size=1,
        rule_costs=Int[adapter.rule_cost(r) for r in ARC.grammar_hodel.rules])
    P.initialize!(iterator)
    outputs=P.local_optimum_outputs(iterator)
    grammar=adapter.property_options.grammar_to_property_grammar(ARC.grammar_hodel)
    costs=Int[adapter.rule_cost(r) for r in grammar.rules]
    shared=Experiments.HerbInterpret.make_output_interpreter(grammar;target_module=ARC,cache_module=ARC)
    function work(legacy,reuse)
        LEGACY_PERIOD[]=legacy
        interp=reuse ? shared : Experiments.HerbInterpret.make_output_interpreter(grammar;target_module=ARC,cache_module=ARC)
        completed=Ref(0)
        rules=Int[]
        # Hashes verify that the compared candidates produce the same output stream.
        digest=Ref(UInt(0))
        counted=(rule,children,specs) -> begin
            completed[] >= LIMIT && throw(CandidateLimit())
            result=interp(rule,children,specs)
            completed[]+=1
            push!(rules,rule)
            digest[]=hash(result,digest[])
            result
        end
        property=nothing
        capped=false
        try
            property=P.find_property!(benchmark=ARC,problem=train,grammar=grammar,
                interpreter=counted,local_optimum_outputs=outputs,
                property_types=adapter.property_options.property_types,max_cost=3,rule_costs=costs)
        catch err
            err isa CandidateLimit || rethrow()
            capped=true
        end
        (completed=completed[],capped=capped,rules_hash=string(hash(rules)),
            outputs_hash=string(digest[]),property_found=!isnothing(property))
    end
    println("Warming shared interpreter with both primitive implementations"); flush(stdout)
    reference=work(true,true)
    @assert reference==work(false,true)
    rows=Any[]
    # Alternate order to reduce systematic timing/order effects.
    for (round,modes) in ((1,((true,false),(false,false),(true,true),(false,true))),
                          (2,((false,true),(true,true),(false,false),(true,false))))
        for (legacy,reuse) in modes
            GC.gc()
            t=@timed work(legacy,reuse)
            @assert t.value==reference
            row=Dict("round"=>round,"legacy_periodicity"=>legacy,"reuse_interpreter"=>reuse,
                "seconds"=>t.time,"allocated_bytes"=>t.bytes,"gc_seconds"=>t.gctime,
                "result"=>t.value)
            push!(rows,row)
            println(JSON3.write(row)); flush(stdout)
        end
    end
    path=isempty(ARGS) ? joinpath(@__DIR__,"arc_property_comparison.json") : abspath(ARGS[1])
    open(path,"w") do io; JSON3.pretty(io,Dict("task"=>problem.name,"candidate_limit"=>LIMIT,"runs"=>rows)); end
end
main()
