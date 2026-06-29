using Pkg
Pkg.activate("../master-thesis")
Pkg.instantiate()
Pkg.update()
Pkg.precompile()

using HerbCore, HerbSearch, HerbConstraints, HerbSpecification, HerbBenchmarks, HerbGrammar, HerbInterpret
using StatsBase, RuntimeGeneratedFunctions, DataStructures, SparseArrays, JSON3

include("io.jl")
include("../src/lazy_cost_based_bus.jl")
include("../src/genetic_iterator.jl")
include("../src/property_synthesizer.jl")
include("../src/phalcon.jl")

repetitions = 1
path = "data/random_phalcon_strings.json"

benchmark = HerbBenchmarks.PBE_SLIA_Track_2019
RuntimeGeneratedFunctions.init(benchmark)

# Remove problems containing "short", "long", "repeat", "small" as they are duplicactes of other with different number of I/O examples
# Results in 124 problems
task_names = [String(s)[9:end] for s in names(benchmark; all=true) if startswith(String(s), "problem_") && all(f -> !occursin(f, String(s)), ["short", "long", "repeat", "small"])]
problems = [getfield(benchmark, Symbol("problem_", name)) for name in task_names]
grammars = [getfield(benchmark, Symbol("grammar_", name)) for name in task_names]

function make_property_grammar(grammar) 
    property_grammar = @cfgrammar begin end

    add_rule!(property_grammar, Expr(:(=), grammar.rules[1], :_arg_out))

    for (type, rule) in zip(grammar.types, grammar.rules)
        rule isa Symbol && occursin("_arg_", string(rule)) && add_rule!(property_grammar, Expr(:(=), type, rule))
    end

    merge_grammars!(property_grammar, @cfgrammar begin
        # Random string operations. Each has a seed such that it is deterministic. The string itself is also contained in the seed to approx random behavior.
        # ntString = random_shuffle(ntString, ntInt)
        # ntString = random_character(ntString, ntInt)
        # ntString = random_substring(ntString, ntInt)

        # Integer constants
        modConst = |(1:5000)

        # Hash value modulo n
        prop = hash_mod_n(ntString, modConst)
        prop = hash_mod_n(ntInt, modConst)
        prop = hash_mod_n(ntBool, modConst)
    end)

    return property_grammar
end

for (problem, grammar) in zip(problems, grammars)
    repetitions_to_perform = repetitions - performed_repetitions(path, problem.name)

    for _ in 1:repetitions_to_perform
        max_length = maximum([max(maximum(length, values(io.in)), length(io.out)) for io in problem.spec])
        rule_costs = Int[rule isa Expr for rule in grammar.rules]

        iterator = GeneticIterator(grammar, :Start,
            benchmark = benchmark,
            problem = problem,
            cost = _ -> 0,
            population_size = 10,
            candidate_pool_size = 2000,
            max_generations_without_improvement = 4,
            max_extension_size = 1,
            max_initial_population_size = 1,
            rule_costs = rule_costs,
            prune_node_by_output = (io, y) -> length(y) > 3*max(maximum(length, values(io.in)), length(io.out))
        )

        result = phalcon(
            iterator = iterator,
            max_number_of_properties = 20,
            property_types = [:prop],
            minimal_increase_property = 0.7,
            max_property_cost = 2,
            rule_costs = rule_costs,
            grammar_to_property_grammar = make_property_grammar
        )

        append_result(path, result)
    end
end