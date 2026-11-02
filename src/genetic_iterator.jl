"""
    abstract type AbstractGeneticIterator <: ProgramIterator end

Abstract type for GeneticIterator. This GeneticIterator works by sequentially creating new populations of programs
by combining programs from the current population and mutating them. Concretely, each generation the following happens:
    1. Create M (candidate_pool_size) candidate individuals, by:
        a. Selecting two random parents A and B from the current population
        b. Crossover:
            - Select a random subprogram from A of a type that exists in B
            - Select a random location from B of that type and replace it with that subprogram
        c. Mutate using one of the following operations:
            - Replace: replace a random subprogram with a random expression up to a certain size/depth of the same type
            - Insert: replace a random subprogram with a random grammar rule that uses that subprogram and fill the rest with random expression up to a certain size/depth
            - Delete: replace a random subprogram with any of its children
            (These mutation operations closely resemble how humans program; we can replace instructions, add lines, remove lines)
    2. Select the best N (population_size) according to a given cost function (cost)
    3. If the total cost of the population has been stable for a certain amount of generations (max_generations_without_improvement), terminate search

Grammar types introduce several difficulties regarding crossovers and mutations:
    - For crossover we need to check which types exists in a program
    - Also for crossover we need to efficiently select uniformly random subprograms of a certain type
    - As not every rule is suitable for insertion and deletation (e.g. String = int_to_string(Int)) we need to efficiently check which rules appear in a program
This necessitates a specialized RuleNode that also stores how many times each rule appears in itself.

"""
abstract type AbstractGeneticIterator <: ProgramIterator end


# Components share the Phalcon module namespace; include order defines their types first.
include("genetic/nodes.jl")
include("genetic/individuals.jl")

@programiterator mutable GeneticIterator(
    # Problem specification
    benchmark = nothing,
    problem = nothing,

    rng::AbstractRNG = Random.default_rng(),

    # Hyperparemeters
    cost::Function = nothing,
    population_size::Int = 10,
    candidate_pool_size::Int = 1000,
    max_generations_without_improvement::Int = 5,
    max_extension_size::Int = 1,
    max_initial_population_size::Int = 2,
    rule_costs::Vector{Int} = [],
    prune_node_by_output::Union{Nothing,Function} = nothing,
    # Maximum retained bytes for one node's complete output vector (1 MiB).
    max_output_bytes::Int = 1024^2,

    # Opt in to retaining parent trees for pretty_print diagnostics.
    track_ancestry::Bool = false,

    # Internal structures
    population::Vector{Individual} = Individual[],
    extensions::DefaultDict{Symbol,Vector{RuleNodeWithRuleCounts}} = DefaultDict{Symbol,Vector{RuleNodeWithRuleCounts}}(() -> RuleNodeWithRuleCounts[]),

    # Caching
    recursive_rules::Vector{Bool} = Bool[],
    rules_in_recursive_rules::Vector{Bool} = Bool[],

    # Optional prebuilt interpreter for this unchanged grammar and benchmark module.
    interpreter = nothing,
    programs_evaluated::Int = 0,
) <: AbstractGeneticIterator

include("genetic/evaluation.jl")
include("genetic/population.jl")
include("genetic/operators.jl")
include("genetic/iteration.jl")
include("genetic/diagnostics.jl")
