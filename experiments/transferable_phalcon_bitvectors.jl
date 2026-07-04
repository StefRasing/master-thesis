using Pkg
Pkg.activate("../master-thesis")
Pkg.instantiate()
Pkg.precompile()

using HerbCore, HerbSearch, HerbConstraints, HerbSpecification, HerbBenchmarks, HerbGrammar, HerbInterpret
using StatsBase, RuntimeGeneratedFunctions, DataStructures, SparseArrays, JSON3, JLD2, Random

include("io.jl")
include("../src/lazy_cost_based_bus.jl")
include("../src/genetic_iterator.jl")
include("../src/property_synthesizer.jl")
# include("../src/transferable_phalcon.jl")
include("../src/strict_transferable_phalcon.jl")

repetitions = 1
run = ARGS[1]
# path =          "data/transferable_phalcon_bitvectors/transferable_phalcon_bitvectors$(run).json"
# property_path = "data/transferable_phalcon_bitvectors/properties/properties$(run).jld2"
path =          "data/strict_transferable_phalcon_bitvectors/strict_transferable_phalcon_bitvectors$(run).json"
property_path = "data/strict_transferable_phalcon_bitvectors/properties/properties$(run).jld2"
store = true

benchmark = HerbBenchmarks.PBE_BV_Track_2018
RuntimeGeneratedFunctions.init(benchmark)

# Only keep problems with 10 or less I/O examples
# Results in 151 problems
task_names = [String(s)[9:end] for s in names(benchmark; all=true) if startswith(String(s), "problem_") && length(getfield(benchmark, s).spec) <= 10]
task_names = shuffle(MersenneTwister(run), task_names)

problems = [getfield(benchmark, Symbol("problem_", name)) for name in task_names]
grammars = [getfield(benchmark, Symbol("grammar_", name)) for name in task_names]


stored_properties = load_properties(property_path)

for (problem, grammar) in zip(problems, grammars)
    performed_repetitions(path, problem.name) > 0 && continue

    rule_cost_func = r -> r isa Expr
    rule_costs = Int[rule_cost_func(rule) for rule in grammar.rules]

    iterator = GeneticIterator(grammar, :Start,
        benchmark = benchmark,
        problem = problem,
        cost = _ -> 0,
        population_size = 20,
        candidate_pool_size = 2000,
        max_generations_without_improvement = 10,
        max_extension_size = 1,
        max_initial_population_size = 1,
        max_size = 50,
        rule_costs = rule_costs,
    )

    result = transferable_phalcon(
        iterator = iterator,
        stored_properties = stored_properties,
        max_number_of_iterations = 20,
        property_types = [:Start],
        max_property_cost = 4,
        rule_cost_func = rule_cost_func,
        verbose = false,
        timeout = 60*30,
    )


    if store
        append_result(path, result)
        store_properties(property_path, stored_properties)
    else
        println()
        @show result
    end
end