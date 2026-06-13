using SparseArrays
using StatsBase
using DataStructures

using HerbCore
using HerbGrammar
using HerbConstraints
using HerbSearch

# ============================================================
# CASYNTH Genetic Search
# Structural heuristic only
# ============================================================

abstract type AbstractGeneticIterator <: ProgramIterator end

# ------------------------------------------------------------
# RuleNode with cached rule counts
# ------------------------------------------------------------

struct RuleNodeWithRuleCounts <: AbstractRuleNode
    rule::Int
    children::Vector{RuleNodeWithRuleCounts}
    rule_counts::SparseVector{Int,Int}
end

HerbCore.isfilled(::RuleNodeWithRuleCounts)::Bool = true
HerbCore.isuniform(::RuleNodeWithRuleCounts)::Bool = true
HerbCore.get_rule(program::RuleNodeWithRuleCounts)::Int = program.rule
HerbCore.get_children(program::RuleNodeWithRuleCounts)::Vector{AbstractRuleNode} = AbstractRuleNode[program.children...]
Base.length(program::RuleNodeWithRuleCounts) = sum(program.rule_counts)

function RuleNodeWithRuleCounts(iter::ProgramIterator, rule::Int, children::Vector{RuleNodeWithRuleCounts})
    rule_counts = SparseVector{Int,Int}(length(iter.solver.grammar.rules), Int[], Int[])
    rule_counts[rule] += 1
    for c in children
        rule_counts += c.rule_counts
    end
    return RuleNodeWithRuleCounts(rule, children, rule_counts)
end

RuleNodeWithRuleCounts(iter::ProgramIterator, program::RuleNode) =
    RuleNodeWithRuleCounts(
        iter,
        program.ind,
        RuleNodeWithRuleCounts[RuleNodeWithRuleCounts(iter, c) for c in program.children]
    )

HerbCore.RuleNode(program::RuleNodeWithRuleCounts) =
    HerbCore.RuleNode(program.rule, [HerbCore.RuleNode(c) for c in program.children])

# ------------------------------------------------------------
# Random subtree selection / replacement
# ------------------------------------------------------------

function random_subtree(iter::ProgramIterator,
                        program::RuleNodeWithRuleCounts,
                        allowed_rules::Vector{Bool})::Tuple{RuleNodeWithRuleCounts,Vector{Int}}
    cs = program.children

    program_weight = allowed_rules[program.rule] ? 1 : 0
    child_weights = [sum(c.rule_counts[allowed_rules]) for c in cs]

    weights = [program_weight; child_weights]
    sum(weights) == 0 && error("random_subtree called with no allowed subtrees")

    index = sample(0:length(cs), Weights(weights))

    index == 0 && return program, Int[]

    node, path = random_subtree(iter, cs[index], allowed_rules)
    return node, [index; path]
end

function replace_at_path(iter::ProgramIterator,
                         program::RuleNodeWithRuleCounts,
                         path::Vector{Int},
                         replacement::RuleNodeWithRuleCounts)::RuleNodeWithRuleCounts
    isempty(path) && return replacement

    idx = first(path)
    rest = path[2:end]

    children = RuleNodeWithRuleCounts[
        i == idx ? replace_at_path(iter, c, rest, replacement) : c
        for (i, c) in enumerate(program.children)
    ]

    return RuleNodeWithRuleCounts(iter, program.rule, children)
end

# ------------------------------------------------------------
# Individuals
# ------------------------------------------------------------

struct Individual
    program::RuleNodeWithRuleCounts
    cost::Float64
end

function Base.isless(a::Individual, b::Individual)
    a.cost != b.cost && return a.cost < b.cost
    return length(a.program) < length(b.program)
end

function Base.:(==)(a::Individual, b::Individual)
    a.cost == b.cost &&
    length(a.program) == length(b.program) &&
    a.program == b.program
end

# ------------------------------------------------------------
# Iterator definition
# ------------------------------------------------------------

@programiterator mutable GeneticIterator(
    problem = nothing,

    heuristic::Function = nothing,
    population_size::Int = 10,
    candidate_pool_size::Int = 1000,
    max_generations_without_improvement::Int = 5,
    max_extension_depth::Int = 1,
    max_extension_size::Int = 1,

    population::Vector{Individual} = Individual[],
    extensions::DefaultDict{Symbol,Vector{RuleNodeWithRuleCounts}} =
        DefaultDict{Symbol,Vector{RuleNodeWithRuleCounts}}(() -> RuleNodeWithRuleCounts[]),

    recursive_rules::Vector{Bool} = Bool[],
    rules_in_recursive_rules::Vector{Bool} = Bool[],
) <: AbstractGeneticIterator

# ------------------------------------------------------------
# Structural heuristic only
# ------------------------------------------------------------

function structural_cost(iter::GeneticIterator, program::RuleNodeWithRuleCounts)::Float64
    rn = HerbCore.RuleNode(program)
    c = iter.heuristic(rn)
    return isnothing(c) || !isfinite(Float64(c)) ? Inf : Float64(c)
end

Individual(iter::GeneticIterator, program::RuleNodeWithRuleCounts) =
    Individual(program, structural_cost(iter, program))

# ------------------------------------------------------------
# Population maintenance
# ------------------------------------------------------------

function add_to_population!(iter::GeneticIterator, program::RuleNodeWithRuleCounts)::Nothing
    grammar = iter.solver.grammar

    if any(!check_tree(constraint, HerbCore.RuleNode(program)) for constraint in grammar.constraints)
        return nothing
    end

    new_individual = Individual(iter, program)
    new_individual.cost == Inf && return nothing

    if length(iter.population) >= iter.population_size && new_individual > iter.population[end]
        return nothing
    end

    costs = [e.cost for e in iter.population]
    first_index = searchsortedfirst(costs, new_individual.cost)
    last_index  = searchsortedlast(costs, new_individual.cost)

    if first_index <= last_index
        for i in first_index:last_index
            if iter.population[i].program == new_individual.program
                return nothing
            end
        end
    end

    index = searchsortedlast(iter.population, new_individual)
    insert!(iter.population, index + 1, new_individual)

    if length(iter.population) > iter.population_size
        pop!(iter.population)
    end

    return nothing
end

# ------------------------------------------------------------
# Initialization
# ------------------------------------------------------------

function initialize!(iter::GeneticIterator)::Nothing
    grammar = iter.solver.grammar
    types = grammar.types

    iter.recursive_rules = [types[rule_id] in grammar.childtypes[rule_id] for rule_id in eachindex(types)]
    recursive_types = unique(types[iter.recursive_rules])
    iter.rules_in_recursive_rules = [t in recursive_types for t in types]

    for T in unique(types)
        seen = Set{RuleNode}()

        for extension in BFSIterator(grammar, T;
                max_depth = iter.max_extension_depth,
                max_size = iter.max_extension_size)

            extension = freeze_state(extension)

            if extension in seen
                continue
            end
            push!(seen, extension)

            wrapped = RuleNodeWithRuleCounts(iter, extension)
            push!(iter.extensions[T], wrapped)
        end
    end

    for program in iter.extensions[get_starting_symbol(iter)]
        add_to_population!(iter, program)
    end

    return nothing
end

# ------------------------------------------------------------
# Genetic operators
# ------------------------------------------------------------

function crossover(iter::GeneticIterator,
                   parent_1::RuleNodeWithRuleCounts,
                   parent_2::RuleNodeWithRuleCounts)::RuleNodeWithRuleCounts
    types = iter.solver.grammar.types

    allowed_types = unique([types[rule] for (rule, rule_count) in enumerate(parent_2.rule_counts) if rule_count > 0])
    allowed_rules = [type in allowed_types for type in types]

    replacement, _ = random_subtree(iter, parent_1, allowed_rules)
    replacement_type = types[replacement.rule]
    replacement_rules = [type == replacement_type for type in types]

    _, replacement_path = random_subtree(iter, parent_2, replacement_rules)

    return replace_at_path(iter, parent_2, replacement_path, replacement)
end

function mutate(iter::GeneticIterator, individual::RuleNodeWithRuleCounts)::RuleNodeWithRuleCounts
    grammar = iter.solver.grammar
    types = grammar.types

    operations = Symbol[:replace]

    if any(count -> count > 0, individual.rule_counts[iter.recursive_rules])
        push!(operations, :delete)
    end

    if any(count -> count > 0, individual.rule_counts[iter.rules_in_recursive_rules])
        push!(operations, :insert)
    end

    operation = rand(operations)

    if operation == :replace
        old_node, replacement_path = random_subtree(iter, individual, [true for _ in types])
        replacement_type = types[old_node.rule]
        replacement = rand(iter.extensions[replacement_type])
        return replace_at_path(iter, individual, replacement_path, replacement)

    elseif operation == :insert
        node, replacement_path = random_subtree(iter, individual, iter.rules_in_recursive_rules)

        node_type = types[node.rule]
        rule_id = rand([rule_id for (rule_id, type) in enumerate(types) if iter.recursive_rules[rule_id] && type == node_type])

        node_index = rand([idx for (idx, type) in enumerate(grammar.childtypes[rule_id]) if type == node_type])

        children = RuleNodeWithRuleCounts[
            idx == node_index ? node : rand(iter.extensions[type])
            for (idx, type) in enumerate(grammar.childtypes[rule_id])
        ]

        replacement = RuleNodeWithRuleCounts(iter, rule_id, children)
        return replace_at_path(iter, individual, replacement_path, replacement)

    else
        node, replacement_path = random_subtree(iter, individual, iter.recursive_rules)
        T = types[node.rule]
        replacement = rand([c for c in node.children if types[c.rule] == T])
        return replace_at_path(iter, individual, replacement_path, replacement)
    end
end

function combine!(iter::GeneticIterator)::Nothing
    old_population = collect(iter.population)

    for _ in 1:iter.candidate_pool_size
        parent_1 = rand(old_population).program
        parent_2 = rand(old_population).program

        child = crossover(iter, parent_1, parent_2)
        child = mutate(iter, child)

        add_to_population!(iter, child)
    end

    return nothing
end

# ------------------------------------------------------------
# Iterator state / iteration
# ------------------------------------------------------------

mutable struct GeneticIteratorState
    queue::Vector{Individual}
    past_population_costs::Vector{Float64}
end

GeneticIteratorState() = GeneticIteratorState(Individual[], Float64[])

function add_new_population!(state::GeneticIteratorState, population::Vector{Individual})::Nothing
    total_cost = sum(Float64[ind.cost for ind in population])
    state.queue = copy(population)
    push!(state.past_population_costs, total_cost)
    return nothing
end

function Base.iterate(iter::GeneticIterator)
    initialize!(iter)
    state = GeneticIteratorState()
    add_new_population!(state, iter.population)
    return Base.iterate(iter, state)
end

function Base.iterate(iter::GeneticIterator, state::GeneticIteratorState)
    if isempty(state.queue)
        n = iter.max_generations_without_improvement
        if length(state.past_population_costs) >= n &&
           allequal(state.past_population_costs[end-n+1:end])
            return nothing
        end

        combine!(iter)
        add_new_population!(state, iter.population)
    end

    return popfirst!(state.queue).program, state
end

# ------------------------------------------------------------
# Convenience constructor for CASYNTH
# ------------------------------------------------------------

"""
Build a structural CASYNTH genetic iterator.

Example:
    heuristic_obj = CASynth.CASynthStructuralHeuristic(...)
    iter = make_casynth_genetic_iterator(grammar, search_symbol, problem, heuristic_obj;
        population_size=50, candidate_pool_size=500,
        max_generations_without_improvement=5,
        max_extension_depth=1, max_extension_size=1)
"""
function make_casynth_genetic_iterator(grammar,
                                       start_symbol,
                                       problem,
                                       heuristic_obj;
                                       population_size::Int=50,
                                       candidate_pool_size::Int=500,
                                       max_generations_without_improvement::Int=5,
                                       max_extension_depth::Int=1,
                                       max_extension_size::Int=1)
    structural_heuristic = CASynth.make_casynth_structural_heuristic(heuristic_obj)

    return GeneticIterator(
        grammar,
        start_symbol;
        problem = problem,
        heuristic = structural_heuristic,
        population_size = population_size,
        candidate_pool_size = candidate_pool_size,
        max_generations_without_improvement = max_generations_without_improvement,
        max_extension_depth = max_extension_depth,
        max_extension_size = max_extension_size,
    )
end