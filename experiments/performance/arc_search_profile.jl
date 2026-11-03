# julia --project=. --startup-file=no experiments/performance/arc_search_profile.jl [output-directory]
# Instrumentation exists only in this process; no production methods are edited on disk.
using Profile, Random, JSON3
include("../src/Experiments.jl")
using .Experiments
const P = Experiments.Phalcon
const ARC = Experiments.HerbBenchmarks.ARC_AGI1
const outdir = isempty(ARGS) ? joinpath(@__DIR__, "results") : abspath(ARGS[1])
mkpath(outdir)

module Counters
const equality_calls = Ref(0)
const equality_ns = Ref(UInt64(0))
const identity_calls = Ref(0)
const combinations_calls = Ref(0)
const combinations_ns = Ref(UInt64(0))
const combinations_bytes = Ref(0)
const combinations_count = Ref(0)
const combinations_max = Ref(0)
function equal(a,b)
    start = time_ns()
    result = Set(a) == Set(b)
    equality_ns[] += time_ns() - start
    equality_calls[] += 1
    identity_calls[] += a === b
    return result
end
function reset!()
    for r in (equality_calls, equality_ns, identity_calls, combinations_calls, combinations_ns,
              combinations_bytes, combinations_count, combinations_max)
        r[] = 0
    end
end
end
@eval ARC begin
    Base.:(==)(a::Indices, b::Indices) = $Counters.equal(a,b)
    Base.:(==)(a::Object, b::Object) = $Counters.equal(a,b)
    equality(a::Object, b::Object)::Bool = $Counters.equal(a,b)
end
# Time only materializing Cartesian products, excluding recursive child-bank construction.
@eval P function program_combinations(iter::LazyCostBasedBus, types::Vector{Symbol}, total_cost::Int)
    combinations = []
    $Counters.combinations_calls[] += 1
    for costs in compositions(total_cost, length(types); deadline=iter.deadline)
        pools = [get_programs(iter, type, cost) for (type, cost) in zip(types, costs)]
        started = time_ns()
        bytes = Base.gc_bytes()
        try
            for children in Iterators.product(pools...)
                _check_deadline(iter.deadline)
                push!(combinations, children)
            end
        finally
            $Counters.combinations_ns[] += time_ns() - started
            $Counters.combinations_bytes[] += Base.gc_bytes() - bytes
        end
    end
    $Counters.combinations_count[] += length(combinations)
    $Counters.combinations_max[] = max($Counters.combinations_max[], length(combinations))
    return combinations
end

function measured(label, f)
    GC.gc()
    Counters.reset!()
    Profile.clear()
    timed = @timed Profile.@profile f()
    data, lidict = Profile.retrieve()
    open(joinpath(outdir, label * ".flat.txt"), "w") do io
        Profile.print(io, data, lidict; format=:flat, sortedby=:count, mincount=2, C=true)
    end
    println("Collecting profile summary for ",label); flush(stdout)
    samples = 0
    current = Set{String}()
    hits = Dict{String,Int}()
    for ip in Profile.fetch(include_meta=false)
        if ip == 0
            if !isempty(current)
                samples += 1
                for key in current; hits[key] = get(hits,key,0)+1; end
            end
            empty!(current)
            continue
        end
        for frame in get(lidict, ip, [])
            fun, file = string(frame.func), string(frame.file)
            push!(current, "all")
            occursin("program_combinations",fun) && push!(current,"combinations_inclusive")
            fun == "grow" && occursin("lazy_cost_based_bus",file) && push!(current,"enumeration_total")
            occursin("equal",fun) && occursin("arc_search_profile",file) && push!(current,"set_equality")
            (occursin("jl_gc",fun) || occursin("gc_collect",fun)) && push!(current,"gc")
            (occursin("typeinf",fun) || occursin("abstract_call",fun) || occursin("jl_compile",fun)) && push!(current,"compilation")
        end
    end
    record = Dict("phase"=>label, "seconds"=>timed.time, "allocated_bytes"=>timed.bytes,
        "gc_seconds"=>timed.gctime, "equality_calls"=>Counters.equality_calls[],
        "equality_seconds"=>Counters.equality_ns[]/1e9, "identity_calls"=>Counters.identity_calls[],
        "combination_calls"=>Counters.combinations_calls[],
        "combination_seconds"=>Counters.combinations_ns[]/1e9,
        "combination_allocated_bytes"=>Counters.combinations_bytes[],
        "combinations"=>Counters.combinations_count[], "largest_combination_batch"=>Counters.combinations_max[],
        "samples"=>samples, "sample_hits"=>hits,
        "result"=>timed.value)
    open(joinpath(outdir,label * ".json"),"w") do io; JSON3.pretty(io,record); end
    println(JSON3.write(record)); flush(stdout)
    return record
end

function main()
    adapter = Experiments.benchmark_adapter(:arc)
    config = Experiments.ExperimentConfig(algorithm=:phalcon, benchmark=:arc, store=false, timeout=12)
    println("Loading/warming representative search paths"); flush(stdout)
    Experiments.warmup_search!(adapter, :arc)
    problems = ARC.training_problems()
    for index in (1, 2, 5)
        problem = problems[index]
        train, _, _ = Experiments.split_problem(problem, [length(problem.spec)])
        println("Preparing ",problem.name); flush(stdout)
        interpreter = Experiments.prepare_interpreter(config,adapter,problem,ARC.grammar_hodel)
        measured("task$(index)_search") do
            Experiments.run_trial(config,adapter,problem,ARC.grammar_hodel;
                rng=Xoshiro(42),interpreter_ref=Ref{Any}(interpreter))
        end
        # Snapshot a real initialized population for a separately measurable property search.
        iterator = P.GeneticIterator(ARC.grammar_hodel,:Start; benchmark=ARC, problem=train,
            interpreter, rng=Xoshiro(42), cost=_ -> 0, population_size=20,
            max_extension_size=1,max_initial_population_size=1,
            rule_costs=Int[adapter.rule_cost(r) for r in ARC.grammar_hodel.rules])
        P.initialize!(iterator)
        outputs = P.local_optimum_outputs(iterator)
        grammar = adapter.property_options.grammar_to_property_grammar(ARC.grammar_hodel)
        costs = Int[adapter.rule_cost(r) for r in grammar.rules]
        property_interpreter = Ref{Any}(nothing)
        function properties(seconds)
            count = Ref(0)
            property = nothing
            timeout = false
            try
                if isnothing(property_interpreter[])
                    property_interpreter[] = Experiments.HerbInterpret.make_output_interpreter(grammar;
                        target_module=ARC, cache_module=ARC)
                end
                property = P.find_property!(benchmark=ARC, problem=train, grammar=grammar,
                    interpreter=property_interpreter[],
                    local_optimum_outputs=outputs, property_types=adapter.property_options.property_types,
                    max_cost=3, rule_costs=costs, deadline=P._search_time()+seconds,
                    properties_enumerated=count)
            catch err
                err isa P.SearchTimeout || rethrow()
                timeout = true
            end
            return Dict("enumerated"=>count[],"timeout"=>timeout,"population_size"=>length(outputs),
                "property_found"=>!isnothing(property))
        end
        properties(3) # bounded warm-up; later specializations can still compile
        measured("task$(index)_properties", () -> properties(12))
    end
end
# Support do-block syntax.
measured(f::Function,label::String) = measured(label,f)
main()
