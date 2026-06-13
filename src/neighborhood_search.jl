abstract type AbstractNeighborhoodSearch <: ProgramIterator end

get_program(entry::PoolEntry) = entry.program
get_cost(entry::PoolEntry) = entry.cost
HerbCore.depth(entry::PoolEntry) = entry.depth
Base.length(entry::PoolEntry) = entry.size

# ------------------------------------------------------------
# Iterator
# ------------------------------------------------------------

@programiterator mutable NeighborhoodSearch(
    problem = nothing,
    heuristic = nothing,

    pool_size::Int = 0,
    max_extension_depth::Int = 1,
    max_extension_size::Int = 1,

    pool::Vector{PoolEntry} = PoolEntry[],
    extensions::Vector{AbstractRuleNode} = AbstractRuleNode[],
) <: AbstractNeighborhoodSearch

highest_cost(iter::NeighborhoodSearch) = iter.pool[end].cost
lowest_cost(iter::NeighborhoodSearch) = iter.pool[begin].cost

function heuristic_cost(iter::NeighborhoodSearch, program::AbstractRuleNode)::Float64
    cost = iter.heuristic(program)
    if isnothing(cost) || !isfinite(Float64(cost))
        return Inf
    end
    return Float64(cost)
end

# ------------------------------------------------------------
# Pool maintenance
# ------------------------------------------------------------

function add_to_pool!(iter::NeighborhoodSearch, program::AbstractRuleNode, parent=nothing)
    grammar = iter.solver.grammar

    if any(!check_tree(constraint, program) for constraint in grammar.constraints)
        return nothing
    end

    cost = heuristic_cost(iter, program)
    cost == Inf && return nothing

    entry = PoolEntry(program, cost, depth(program), length(program); parent=parent)

    if length(iter.pool) >= iter.pool_size && entry >= iter.pool[end]
        return nothing
    end

    # only compare syntactically against equal-cost region
    costs = [e.cost for e in iter.pool]
    first_index = searchsortedfirst(costs, entry.cost)
    last_index  = searchsortedlast(costs, entry.cost)

    if first_index <= last_index
        for i in first_index:last_index
            if iter.pool[i].program == program
                return nothing
            end
        end
    end

    index = searchsortedlast(iter.pool, entry)
    insert!(iter.pool, index + 1, entry)

    if length(iter.pool) > iter.pool_size
        pop!(iter.pool)
    end

    return nothing
end

# ------------------------------------------------------------
# Initialization
# ------------------------------------------------------------

function initialize!(iter::NeighborhoodSearch)
    original_grammar = iter.solver.grammar
    grammar = deepcopy(original_grammar)
    clearconstraints!(grammar)

    start_symbol = get_starting_symbol(iter.solver)

    for T in unique(grammar.types)
        isnothing(T) && continue

        extensions = BFSIterator(
            grammar,
            T;
            max_depth = iter.max_extension_depth,
            max_size = iter.max_extension_size,
        )

        for extension in extensions
            extension = freeze_state(extension)

            # avoid duplicate extensions syntactically
            if any(e -> e == extension, iter.extensions)
                continue
            end

            push!(iter.extensions, extension)

            if T == start_symbol &&
               all(check_tree(constraint, extension) for constraint in original_grammar.constraints)
                add_to_pool!(iter, extension)
            end
        end
    end

    return nothing
end

# ------------------------------------------------------------
# Neighborhood generation
# ------------------------------------------------------------

function neighborhood(iter::NeighborhoodSearch, program::AbstractRuleNode)
    grammar = iter.solver.grammar
    types = grammar.types

    function extend(node::AbstractRuleNode)
        node_type = types[get_rule(node)]
        combinations = Set{AbstractRuleNode}()

        for rule_id in eachindex(grammar.rules)
            if types[rule_id] != node_type
                continue
            end

            childtypes = grammar.childtypes[rule_id]
            isempty(childtypes) && continue

            for node_index in findall(t -> t == node_type, childtypes)
                child_options = Vector{Vector{AbstractRuleNode}}()

                for (idx, child_type) in enumerate(childtypes)
                    if idx == node_index
                        push!(child_options, AbstractRuleNode[node])
                    else
                        push!(child_options,
                              AbstractRuleNode[e for e in iter.extensions if child_type == types[get_rule(e)]])
                    end
                end

                for child_tuple in Iterators.product(child_options...)
                    children = collect(child_tuple)
                    push!(combinations, RuleNode(rule_id, children))
                end
            end
        end

        return combinations
    end

    function extend_all_nodes(node::AbstractRuleNode)
        results = extend(node)

        children = HerbCore.get_children(node)
        for (child_index, child) in enumerate(children)
            for new_child in extend_all_nodes(child)
                new_children = AbstractRuleNode[
                    i == child_index ? new_child : c for (i, c) in enumerate(children)
                ]
                push!(results, RuleNode(get_rule(node), new_children))
            end
        end

        return results
    end

    return extend_all_nodes(program)
end

# ------------------------------------------------------------
# Expansion
# ------------------------------------------------------------

function combine!(iter::NeighborhoodSearch)
    neighbor_to_parent = Dict{AbstractRuleNode,Tuple{PoolEntry,Int}}()

    for (i, pool_entry) in enumerate(iter.pool)
        if pool_entry.has_been_expanded
            continue
        end

        for neighbor in neighborhood(iter, pool_entry.program)
            if !haskey(neighbor_to_parent, neighbor)
                neighbor_to_parent[neighbor] = (pool_entry, i)
            end
        end

        pool_entry.has_been_expanded = true
    end

    # smaller programs first
    sorted = sort(collect(neighbor_to_parent), by = x -> length(first(x)))

    for (neighbor, parent) in sorted
        add_to_pool!(iter, neighbor, parent)
    end

    return [pool_entry.program for pool_entry in iter.pool if !pool_entry.has_been_expanded]
end

# ------------------------------------------------------------
# Iteration protocol
# ------------------------------------------------------------

function Base.iterate(iter::NeighborhoodSearch)
    initialize!(iter)
    return Base.iterate(iter, [pool_entry.program for pool_entry in iter.pool])
end

function Base.iterate(iter::NeighborhoodSearch, state::Vector{<:AbstractRuleNode})
    if isempty(state)
        state = combine!(iter)
    end

    if isempty(state)
        return nothing
    end

    return popfirst!(state), state
end

# ------------------------------------------------------------
# Convenience constructor for CASYNTH
# ------------------------------------------------------------

"""
Build a NeighborhoodSearch iterator that uses the CASYNTH structural heuristic.

Example:
    cost_model = CASynth.CASynthBeamCostModel(...)
    iter = make_casynth_neighborhood_iterator(grammar, search_symbol, problem, cost_model;
        pool_size=100, max_extension_depth=1, max_extension_size=1,
        max_depth=8, max_size=10)
"""
function make_casynth_neighborhood_iterator(grammar,
                                            start_symbol,
                                            problem,
                                            cost_model;
                                            pool_size::Int=100,
                                            max_extension_depth::Int=1,
                                            max_extension_size::Int=1,
                                            max_depth::Int=typemax(Int),
                                            max_size::Int=typemax(Int))
    beam_cost = CASynth.make_casynth_beam_cost(cost_model)
    structural_heuristic = p -> beam_cost(p, nothing)

    return NeighborhoodSearch(
        grammar,
        start_symbol;
        problem = problem,
        heuristic = structural_heuristic,
        pool_size = pool_size,
        max_extension_depth = max_extension_depth,
        max_extension_size = max_extension_size,
        max_depth = max_depth,
        max_size = max_size,
    )
end