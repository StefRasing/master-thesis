const SelectiveReplay = IdDict{Tuple{Int,Tuple},Union{Nothing,CachedRuleNode}}

struct SelectiveChildBus <: AbstractResumableCostBus
    bus::LazyCostBasedBus
    cursors::Dict{Tuple{Symbol,Int},ResumableBucketCursor}
    required_rule::Int
    containing_hashes::DefaultDict{Symbol,Set{UInt64}}
    containing_nodes::IdDict{CachedRuleNode,Nothing}
    replay::Dict{Tuple{Symbol,Int},SelectiveReplay}
end

"""
    SelectiveContainsCostBasedBus(grammar, types, max_cost, rule_costs,
                                  program_to_outputs, prune_by_output; kwargs...)

Enumerate only products with the first `Contains` rule at the root or in
one of the children. Deduplicate containing and non-containing programs
separately. Complete each cost for use as child pools before advancing,
reusing candidates already evaluated by the selective pass.
"""
struct SelectiveContainsCostBasedBus <: AbstractResumableCostBus
    bus::LazyCostBasedBus
    cursors::Dict{Tuple{Symbol,Int},ResumableBucketCursor}
    children::SelectiveChildBus
end

function SelectiveContainsCostBasedBus(grammar::AbstractGrammar, types::Vector{Symbol}, max_cost::Int,
                                       rule_costs::Vector{Int}, program_to_outputs, prune_by_output; kwargs...)
    index = findfirst(c -> c isa Contains, grammar.constraints)
    index === nothing && throw(ArgumentError("SelectiveContainsCostBasedBus requires a Contains constraint"))
    args = (grammar, types, max_cost, rule_costs, program_to_outputs, prune_by_output)
    children = SelectiveChildBus(LazyCostBasedBus(args...; kwargs...),
        Dict{Tuple{Symbol,Int},ResumableBucketCursor}(), grammar.constraints[index].rule,
        DefaultDict{Symbol,Set{UInt64}}(() -> Set{UInt64}()),
        IdDict{CachedRuleNode,Nothing}(), Dict{Tuple{Symbol,Int},SelectiveReplay}())
    return SelectiveContainsCostBasedBus(LazyCostBasedBus(args...; kwargs...),
        Dict{Tuple{Symbol,Int},ResumableBucketCursor}(), children)
end

function _assemble_selective(iter::SelectiveChildBus, rule, children, contains)
    hashes = contains ? iter.containing_hashes : iter.bus.seen_outputs_hashes
    program = assemble(iter.bus, rule, CachedRuleNode[children...], hashes)
    if contains && program !== nothing
        iter.containing_nodes[program] = nothing
    end
    return program
end

function _complete_selective_candidate(iter, replay, rule, children)
    contains = rule == iter.required_rule || any(child -> haskey(iter.containing_nodes, child), children)
    if contains && replay !== nothing
        key = (rule, children)
        haskey(replay, key) && return replay[key]
    end
    return _assemble_selective(iter, rule, children, contains)
end

function _resumable_candidates(iter::SelectiveChildBus, type::Symbol, cost::Int)
    bus = iter.bus
    grammar = bus.grammar
    replay = get(iter.replay, (type, cost), nothing)
    return Iterators.filter(!isnothing, (
        _complete_selective_candidate(iter, replay, rule, children)
        for (rule, rule_type) in enumerate(grammar.types) if rule_type == type
        for children in Iterators.flatten(_resumable_products(
            pools -> Iterators.product(pools...), iter, grammar.childtypes[rule], cost - bus.rule_costs[rule]))
    ))
end

# Visit the last child on the outside, just as Iterators.product does.
# A matching last child permits every prefix. Otherwise recurse only into
# matching prefixes, and skip that choice altogether if there are none.
function _matching_child_product(iter::SelectiveChildBus, pools, n)
    n == 0 && return (), false
    matching_prefix, prefix_can_match = _matching_child_product(iter, pools, n - 1)
    pool = pools[n]
    matching = [haskey(iter.containing_nodes, child) for child in pool]
    choices = prefix_can_match ? eachindex(pool) : findall(matching)
    all_prefixes = Iterators.product(view(pools, 1:(n - 1))...)
    product = Iterators.flatmap(choices) do i
        prefixes = matching[i] ? all_prefixes : matching_prefix
        ((children..., pool[i]) for children in prefixes)
    end
    return product, !isempty(choices)
end

function _selective_product(iter, rule, pools)
    any(isempty, pools) && return ()
    rule == iter.required_rule && return Iterators.product(pools...)
    return first(_matching_child_product(iter, pools, length(pools)))
end

function _resumable_candidates(iter::SelectiveContainsCostBasedBus, type::Symbol, cost::Int)
    child_bus = iter.children
    if haskey(child_bus.bus.bank[type], cost)
        programs = get_programs(child_bus, type, cost)
        return Iterators.filter(program -> haskey(child_bus.containing_nodes, program), programs)
    end

    replay = get!(SelectiveReplay, child_bus.replay, (type, cost))
    grammar = iter.bus.grammar
    return Iterators.filter(!isnothing, (
        get!(() -> _assemble_selective(child_bus, rule, children, true), replay, (rule, children))
        for (rule, rule_type) in enumerate(grammar.types) if rule_type == type
        for children in Iterators.flatten(_resumable_products(
            pools -> _selective_product(child_bus, rule, pools), child_bus,
            grammar.childtypes[rule], cost - iter.bus.rule_costs[rule]))
    ))
end

function _finish_cost!(iter::SelectiveContainsCostBasedBus, cost::Int)
    for type in iter.bus.types
        get_programs(iter.children, type, cost)
        delete!(iter.children.replay, (type, cost))
    end
    return nothing
end
