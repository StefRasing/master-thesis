"""Exploratory domain-wide property ranking; run with --help for options."""
module StringPropertyRanking

if !isdefined(parentmodule(@__MODULE__), :Experiments)
    Base.include(parentmodule(@__MODULE__), joinpath(@__DIR__, "../src/Experiments.jl"))
end
using ..Experiments
using HerbCore, HerbGrammar, HerbConstraints, HerbInterpret, HerbBenchmarks, JSON3
using Dates, SHA
const P = Experiments.Phalcon

Base.@kwdef struct RankingConfig
    programs::Int = 400
    max_program_cost::Int = 6
    max_property_cost::Int = 3
    sampling_timeout::Float64 = 120.0
    ranking_timeout::Float64 = 3600.0
    max_output_bytes::Int = 21 * 1024^2
    cache_bytes::Int = 512 * 1024^2
    prune_zero_acceptance::Bool = true
    canonical_only::Bool = false
    task_limit::Int = typemax(Int)
    output::String = joinpath(@__DIR__, "results", "string_property_ranking.json")
end

function string_tasks(config)
    benchmark = HerbBenchmarks.PBE_SLIA_Track_2019
    names_ = sort!([String(s)[9:end] for s in names(benchmark; all=true)
        if startswith(String(s), "problem_")])
    tasks = NamedTuple[]
    excluded = Dict{String,String}()
    for name in names_
        if config.canonical_only && any(s -> occursin(s, name), ("short", "long", "repeat", "small"))
            excluded[name] = "excluded benchmark variant"
            continue
        end
        problem = getfield(benchmark, Symbol("problem_", name))
        if !Experiments.is_string_to_string(problem)
            excluded[name] = "requires exactly one string input and one string output"
            continue
        end
        push!(tasks, (; problem, grammar=getfield(benchmark, Symbol("grammar_", name))))
    end
    isempty(tasks) && error("No qualifying string tasks")
    selected = tasks[1:min(length(tasks), config.task_limit)]
    return selected, tasks, excluded
end

# Intersect typed productions, including literal types (Bool is not Int), so every
# property is portable. Build using the full eligible suite, even for a task pilot.
function shared_property_grammar(tasks)
    first_grammar = first(tasks).grammar
    rules = Expr[]
    for (type, rule) in zip(first_grammar.types, first_grammar.rules)
        type == :Start && continue
        all(t -> any(type == other_type && typeof(rule) == typeof(other_rule) &&
            isequal(rule, other_rule) for (other_type, other_rule) in
            zip(t.grammar.types, t.grammar.rules)), tasks) || continue
        assignment = Expr(:(=), type, rule)
        any(r -> isequal(r, assignment), rules) || push!(rules, assignment)
    end
    push!(rules, :(ntString = _arg_out))
    grammar = HerbGrammar.expr2csgrammar(Expr(:block, rules...))
    # No Start aliases: every nonterminal-bearing production must have positive
    # cost, ensuring finite enumeration under the operation-count bound.
    all(isempty(ct) || r isa Expr for (r, ct) in zip(grammar.rules, grammar.childtypes)) ||
        error("Shared property grammar contains a zero-cost recursive production")
    return grammar
end

function sample_programs(task, config)
    grammar, problem = task.grammar, task.problem
    deadline = P._search_time() + config.sampling_timeout
    interp = HerbInterpret.make_output_interpreter(grammar;
        target_module=HerbBenchmarks.PBE_SLIA_Track_2019)
    evaluated = Ref(0)
    bus = P.LazyCostBasedBus(grammar, [:Start], config.max_program_cost,
        Int[r isa Expr for r in grammar.rules], (rule, children) -> begin
            evaluated[] += 1
            interp(rule, children, problem.spec)
        end, isnothing; max_output_bytes=config.max_output_bytes, deadline)
    outputs, expressions = Vector[], String[]
    targets = [ex.out for ex in problem.spec]
    solutions_excluded = 0
    for program in bus
        # Keep solutions available as intermediate subprograms in the enumerator,
        # but never include their complete output vectors in the sampled pool.
        if program.outputs == targets
            solutions_excluded += 1
            continue
        end
        push!(outputs, program.outputs)
        push!(expressions, string(rulenode2expr(program, grammar)))
        length(outputs) == config.programs && break
    end
    length(outputs) == config.programs || error("$(problem.name): found only $(length(outputs)) valid, behaviorally distinct non-solution programs within cost $(config.max_program_cost); increase --max-program-cost")
    return (; outputs, expressions, evaluated=evaluated[], solutions_excluded)
end

const acceptance_count = P._domain_agreement

function property_context(task, sample)
    examples = task.problem.spec
    # Explicitly keep the outer vector: each element is one program's complete
    # output vector, preceded by the target output vector.
    outputs = vcat([[ex.out for ex in examples]], sample.outputs)
    return [Dict{Symbol,Any}(:_arg_1 => ex.in[:_arg_1], :_arg_out => value)
        for values in outputs for (ex, value) in zip(examples, values)]
end

foreach_property(visit, grammar, max_cost; deadline=Inf) =
    P._foreach_domain_property(visit, grammar, [:ntString, :ntInt, :ntBool],
        Int[r isa Expr for r in grammar.rules], max_cost; deadline)

const PropertyOutputCache = P.DomainPropertyOutputCache
const output_bytes_bound = P._domain_output_bytes_bound
const evaluate_property = P._evaluate_domain_property

function rank_properties(tasks, samples, grammar, config; io=stdout)
    contexts = [property_context(t, s) for (t, s) in zip(tasks, samples)]
    interp = HerbInterpret.make_output_interpreter(grammar;
        target_module=HerbBenchmarks.PBE_SLIA_Track_2019)
    deadline = P._search_time() + config.ranking_timeout
    ranked = Dict{String,Any}[]
    invalid_counts = Dict("zero_acceptance" => 0, "invalid_target_value" => 0,
        "output_limit" => 0)
    cache = PropertyOutputCache(config.cache_bytes)
    enumerated = 0
    complete = true
    try
        foreach_property(grammar, config.max_property_cost; deadline) do program, type, cost
            enumerated += 1
            enumerated % 1000 == 0 && println(io, "Scoring property $enumerated; $(length(ranked)) valid so far")
            counts = Int[]
            for (task_index, (task, context)) in enumerate(zip(tasks, contexts))
                P._check_deadline(deadline)
                values = evaluate_property(interp, program, context, cache, task_index)
                # Avoid summarysize allocations for ordinary large string batches.
                # A conservative bound can accept safely; rejection still uses
                # the original exact check, preserving output-limit semantics.
                if output_bytes_bound(values) > config.max_output_bytes &&
                        !P._within_output_limit(values, config.max_output_bytes)
                    invalid_counts["output_limit"] += 1
                    return
                end
                accepted = acceptance_count(values, length(task.problem.spec), config.programs)
                if isnothing(accepted)
                    invalid_counts["invalid_target_value"] += 1
                    return
                elseif accepted == 0 && config.prune_zero_acceptance
                    invalid_counts["zero_acceptance"] += 1
                    return
                end
                push!(counts, accepted)
            end
            push!(ranked, Dict("property" => string(rulenode2expr(program, grammar)),
                "type" => string(type), "cost" => cost, "score" => sum(counts),
                "acceptance_by_task" => counts))
        end
    catch err
        err isa P.SearchTimeout || rethrow()
        complete = false
    end
    sort!(ranked; by=r -> (r["score"], r["cost"], r["type"], r["property"]))
    return (; ranked, invalid_counts, enumerated, complete)
end

function run(config=RankingConfig(); io=stdout)
    config.cache_bytes >= 0 || throw(ArgumentError("cache bytes must be nonnegative"))
    config.programs > 0 && config.task_limit > 0 || throw(ArgumentError("positive program/task counts required"))
    config.max_program_cost >= 0 && config.max_property_cost >= 0 || throw(ArgumentError("cost bounds must be nonnegative"))
    config.sampling_timeout > 0 && config.ranking_timeout > 0 || throw(ArgumentError("timeouts must be positive"))
    tasks, eligible, excluded = string_tasks(config)
    grammar = shared_property_grammar(eligible)
    println(io, "$(length(tasks)) selected / $(length(eligible)) eligible tasks; $(config.programs) programs each")
    samples = map(enumerate(tasks)) do (index, task)
        println(io, "Sampling $index/$(length(tasks)): $(task.problem.name)")
        sample_programs(task, config)
    end
    println(io, "Ranking properties through cost $(config.max_property_cost)")
    result = rank_properties(tasks, samples, grammar, config; io)
    report = Dict("created_at" => string(now()), "complete" => result.complete,
        "script_sha256" => bytes2hex(sha256(read(@__FILE__))),
        "benchmark_data_sha256" => bytes2hex(sha256(read(joinpath(dirname(pathof(HerbBenchmarks)), "data/SyGuS/PBE_SLIA_Track_2019/data.jl")))),
        "configuration" => Dict(string(f) => getfield(config, f) for f in fieldnames(RankingConfig)),
        "selection" => "one string input _arg_1, one string output; all supplied examples; no holdout",
        "program_order" => "cost-ordered LazyCostBasedBus; behavioral deduplication on each task; nothing outputs and training solutions excluded; continue until the requested number of non-solutions is collected",
        "property_grammar" => [string(Expr(:(=), t, r)) for (t,r) in zip(grammar.types, grammar.rules)],
        "property_grammar_policy" => "intersection of typed productions over all eligible tasks, plus ntString = _arg_out",
        "score" => config.prune_zero_acceptance ?
            "sum of whole-program acceptance counts; invalid if any task has zero acceptance; ascending rank" :
            "sum of whole-program acceptance counts including zeros; ascending rank",
        "tasks" => [Dict("name" => t.problem.name, "examples" => length(t.problem.spec),
            "sampled_programs" => s.expressions, "programs_evaluated_including_intermediates" => s.evaluated,
            "solutions_excluded" => s.solutions_excluded,
            "sampled_solutions" => count(==([ex.out for ex in t.problem.spec]), s.outputs))
            for (t,s) in zip(tasks,samples)],
        "excluded_tasks" => excluded, "eligible_task_count" => length(eligible),
        "properties_enumerated" => result.enumerated, "invalid_counts" => result.invalid_counts,
        "ranking" => result.ranked)
    mkpath(dirname(abspath(config.output)))
    open(config.output, "w") do out
        JSON3.pretty(out, report)
        println(out)
    end
    println(io, "Saved $(length(result.ranked)) valid properties to $(config.output); complete=$(result.complete)")
    return report
end

function main(args=ARGS)
    if "--help" in args
        println("""
        julia --project=. experiments/research/rank_string_properties.jl [options]
          --programs N                 default 400 (exact count required per task)
          --max-program-cost N         default 6, function applications count as 1
          --max-property-cost N        default 3, matching PHALCON's operation cost
          --sampling-timeout SECONDS   default 120 per task (failure aborts)
          --ranking-timeout SECONDS    default 3600 (saves partial ranking, complete=false)
          --cache-bytes N              default 536870912; 0 disables subtree caching
          --keep-zero-acceptance       retain zero-acceptance properties (default: prune)
          --canonical-only            exclude short/long/repeat/small benchmark variants
          --tasks N                   deterministic pilot on first N eligible tasks
          --output PATH               default experiments/research/results/string_property_ranking.json
        """)
        return
    end
    options = Dict{Symbol,Any}()
    fields = Dict("--cache-bytes" => (:cache_bytes, Int), "--programs" => (:programs, Int), "--max-program-cost" => (:max_program_cost, Int),
        "--max-property-cost" => (:max_property_cost, Int), "--sampling-timeout" => (:sampling_timeout, Float64),
        "--ranking-timeout" => (:ranking_timeout, Float64), "--tasks" => (:task_limit, Int))
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--keep-zero-acceptance"
            options[:prune_zero_acceptance] = false
        elseif arg == "--canonical-only"
            options[:canonical_only] = true
        else
            index < length(args) || throw(ArgumentError("missing value for $arg"))
            if arg == "--output"
                options[:output] = args[index+1]
            else
                haskey(fields, arg) || throw(ArgumentError("unknown option $arg"))
                name, type = fields[arg]
                options[name] = parse(type, args[index+1])
            end
            index += 1
        end
        index += 1
    end
    run(RankingConfig(; options...))
end
end

if abspath(PROGRAM_FILE) == @__FILE__
    StringPropertyRanking.main()
end
