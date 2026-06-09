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

repetitions = 5
path = "data/nonsense_phalcon_strings.json"

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
        # Nonsense string-producing operations
        ntString = sandwich(ntString, ntString)                     # Insert second string in the middle of the first
        ntString = rotate_left(ntString, ntInt)                     # Cyclically rotate characters left by n positions
        ntString = rotate_right(ntString, ntInt)                    # Cyclically rotate characters right by n positions
        ntString = mirror_concat(ntString)                          # Append the reverse of the string to itself
        ntString = every_other(ntString)                            # Keep every second character
        ntString = drop_middle(ntString)                            # Remove the middle character
        ntString = duplicate_middle(ntString)                       # Duplicate the middle character
        ntString = reverse_halves(ntString)                         # Swap the first and second halves
        ntString = interleave(ntString, ntString)                   # Alternate characters from two strings
        ntString = zip_reverse(ntString, ntString)                  # Interleave one string with the reverse of another
        ntString = alternating_case(ntString)                       # Alternate upper/lower case characters
        ntString = surround_with_length(ntString)                   # Prefix and suffix with the string length

        # Weird integer constants
        ntInt = -1 | 0 | 3 | 12 | 42

        # Useless string statistics
        ntInt = ascii_sum(ntString)                                 # Sum of character code values
        ntInt = num_runs(ntString)                                  # Number of consecutive character runs
        ntInt = palindrome_score(ntString)                          # Number of mirrored character matches
        ntInt = hash_mod_17(ntString)                               # Hash value modulo 17
        ntInt = hash_mod_31(ntString)                               # Hash value modulo 31
        ntint = ascii_sum_mod_7(ntString)                           # Character-code sum modulo 7

        # Odd statistical predicates
        ntBool = even_ascii_sum(ntString)                           # Sum of character codes is even
        ntBool = vowel_count_equals_digit_count(ntString)           # Vowel count equals digit count
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
            property_types = [:ntString, :ntInt, :ntBool],
            minimal_increase_property = 0.7,
            max_property_cost = 2,
            rule_costs = rule_costs,
            grammar_to_property_grammar = make_property_grammar
        )

        append_result(path, result)
    end
end