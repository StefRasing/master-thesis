using Pkg
Pkg.activate("../master-thesis")
Pkg.instantiate()
Pkg.precompile()

using HerbCore, HerbSearch, HerbConstraints, HerbSpecification, HerbBenchmarks, HerbGrammar, HerbInterpret
using DataFrames, RuntimeGeneratedFunctions, Plots, DataStructures
using HerbBenchmarks.PBE_SLIA_Track_2019

include("../../../src/phalcon_generalized_properties.jl")
include("../../../plots/problems_sover_over_number_of_properties.jl")
include("../../../plots/time_over_solution_size.jl")
include("../../../plots/time_over_number_of_properties.jl")


#====================================

    Step 1: Setup

=====================================#

benchmark = HerbBenchmarks.PBE_SLIA_Track_2019
RuntimeGeneratedFunctions.init(benchmark)

# Remove problems containing "short", "long", "repeat" as they are duplicactes of other with different number of I/O examples
# univ problems have too many terminals to run in a descent amount of time...
# Also, cut off I/O examples if there are more than 10, otherwise it will take too long
task_names = [String(s)[9:end] for s in names(benchmark; all=true) if startswith(String(s), "problem_") && all(f -> !occursin(f, String(s)), ["short", "long", "repeat", "univ"])]
problems = [getfield(benchmark, Symbol("problem_", name)) for name in task_names]
grammars = [getfield(benchmark, Symbol("grammar_", name)) for name in task_names]
problems = [Problem(problem.name, problem.spec[1:min(end, 10)]) for problem in problems]

#= Define function that extends a given grammar into the property grammar. This handles the following:
    - Set starting symbol to boolean
    - Extend grammar with simple integers / boolean rules for expressivity
    - Imply constraints on the grammar
    - Add the 'y' rule
=#
function grammar_to_property_grammar(grammar)
    property_grammar = deepcopy(grammar)

    # Set start rule to boolean
    original_starting_symbol = property_grammar.rules[1]
    property_grammar.rules[1] = :ntBool

    # Add extra rules for property expressivity
    merge_grammars!(property_grammar, @cfgrammar begin
        ntInt = 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9
        ntBool = ntString == ntString
        ntBool = ntInt == ntInt
        ntBool = ntInt <= ntInt
        ntBool = ntInt < ntInt
    end)    

    # Break symmetries a + b <> b + a and a == b <> b == a
    symmetric_rules = [rule isa Expr && rule.args[1] in [:+, :(==)] for  rule in property_grammar.rules]
    addconstraint!(property_grammar, Ordered(DomainRuleNode(symmetric_rules, [VarNode(:a), VarNode(:b)]), [:a, :b]))

    # Forbid if false/true then ... else ...
    if_rules = [rule isa Expr && rule.head in [:if] for rule in property_grammar.rules]
    true_false_rules = [rule in [true, false] for rule in property_grammar.rules]
    addconstraint!(property_grammar, Forbidden(DomainRuleNode(if_rules, [DomainRuleNode(true_false_rules, []), VarNode(:A), VarNode(:B)])))

    # Forbid if ... then S1 else S1
    addconstraint!(property_grammar, Forbidden(DomainRuleNode(if_rules, [VarNode(:A), VarNode(:B), VarNode(:B)])))

    # Add 'y' rule and constraint grammar to contain it
    add_rule!(property_grammar, Expr(:(=), original_starting_symbol, :_arg_out))
    addconstraint!(property_grammar, Contains(length(property_grammar.rules)))

    return property_grammar
end


#====================================

    Step 2: Define synth function

=====================================#

function path_to_solution(pool_entry)
    if isnothing(pool_entry.parent)
        return []
    end

    (p, i) = pool_entry.parent
    entry = (
        :program => p.program,
        :cost => p.cost,
        :pool_index => i,
    )
    
    return [path_to_solution(p); entry]
end

function phalcon_synthesizer(;
    iterator::PhalconGeneralizedProperties,
    problem::Problem,
)
    println("Starting $(problem.name)")
    # Collect stats: program enumerated and solution
    solution = missing

    # Loop over programs
    for program in iterator
        # Success: all I/O examples solved
        all(output == io.out for (output, io) in zip(program._val, problem.spec)) && (solution = program; break)
    end

    println("Finished $(problem.name)")

    # Return results
    (
        :problem_name => problem.name,
        :solved => !ismissing(solution),
        :solution => solution,
        :programs_enumerated => iterator.programs_evaluated,
        :properties_evaluated => iterator.properties_evaluated,
        :path_to_solution => ismissing(solution) ? missing : path_to_solution(iterator.pool[findfirst(e -> e.program == solution, iterator.pool)]),
        :heuristic => (
            :number_of_candidate_properties => length(iterator.candidate_properties),
            :selected_properties => iterator.selected_properties
        ),
    )
end

function levenshtein_fast(a::AbstractString, b::AbstractString)
    m, n = length(a), length(b)

    if m < n
        a, b = b, a
        m, n = n, m
    end

    prev = collect(0:n)
    curr = similar(prev)

    for i in 1:m
        curr[1] = i
        for j in 1:n
            cost = a[i] == b[j] ? 0 : 1
            curr[j+1] = min(
                prev[j+1] + 1,
                curr[j] + 1,
                prev[j] + cost
            )
        end
        prev, curr = curr, prev
    end

    return prev[n+1]
end


#====================================

    Step 3: Define default parameters

=====================================#

# Define default hyperparameters
params = (
    pool_size = 10,
    max_extension_depth = 1,
    max_extension_size = 1,
    max_property_depth = 4,
    max_property_size = 6,
    max_number_of_properties = 10,

    increase_percentage_threshold = 0.75,
)

arguments = (
    synth = phalcon_synthesizer,
    benchmark = benchmark,
    grammar_to_property_grammar = grammar_to_property_grammar,
    normalized_distance_functions = Dict(
        :ntBool => (a, b) -> a != b,
        :ntInt => (a, b) -> abs(a - b) / (abs(a - b) + 1),
        :ntString => (a, b) -> levenshtein_fast(a, b) / (levenshtein_fast(a, b) + 1)
    )
)

#====================================

    Step 4: Benchmark

=====================================#


ids = 2:2
problems = problems[ids]
grammars = grammars[ids]

data = @benchmark PhalconGeneralizedProperties params=params problems=problems grammars=grammars args=arguments