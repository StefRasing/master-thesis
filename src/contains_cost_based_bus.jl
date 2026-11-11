struct DeferredContainsProduct
    cursor::ResumableBucketCursor
    programs::Vector{CachedRuleNode}
end

"""
    ContainsCostBasedBus(grammar, types, max_cost, rule_costs,
                         program_to_outputs, prune_by_output; kwargs...)

Enumerate in the order of `ResumableCostBasedBus` for a grammar with a
`Contains` constraint. Defer child combinations after the last tuple that
can satisfy the constraint. Finish deferred work before it can affect
first-seen deduplication or be needed as a child pool. Interpreter calls
for different types may be reordered, so evaluation must be deterministic.
"""
struct ContainsCostBasedBus <: AbstractResumableCostBus
    bus::LazyCostBasedBus
    cursors::Dict{Tuple{Symbol,Int},ResumableBucketCursor}
    constraint::Contains
    deferred::Dict{Symbol,Vector{DeferredContainsProduct}}
    last_matches::IdDict{Vector{CachedRuleNode},Int}
end

function ContainsCostBasedBus(grammar::AbstractGrammar, types::Vector{Symbol}, max_cost::Int,
                              rule_costs::Vector{Int}, program_to_outputs, prune_by_output; kwargs...)
    index = findfirst(c -> c isa Contains, grammar.constraints)
    index === nothing && throw(ArgumentError("ContainsCostBasedBus requires a Contains constraint"))
    bus = LazyCostBasedBus(grammar, types, max_cost, rule_costs, program_to_outputs,
        prune_by_output; kwargs...)
    return ContainsCostBasedBus(bus, Dict{Tuple{Symbol,Int},ResumableBucketCursor}(),
        grammar.constraints[index], Dict{Symbol,Vector{DeferredContainsProduct}}(),
        IdDict{Vector{CachedRuleNode},Int}())
end

function _flush_deferred!(iter::ContainsCostBasedBus, type::Symbol)
    deferred = get(iter.deferred, type, nothing)
    deferred === nothing && return nothing
    for entry in deferred
        while _advance_cursor!(entry.cursor, entry.programs) !== nothing
        end
    end
    delete!(iter.deferred, type)
    return nothing
end

function _finish_cost!(iter::ContainsCostBasedBus, ::Int)
    for type in iter.bus.types
        _flush_deferred!(iter, type)
    end
end

# The first child varies fastest in Iterators.product. The latest matching
# tuple sets every other child to its last index and uses the least significant
# child that has a match, unless another child already matches at its last index.
function _split_contains_product(iter::ContainsCostBasedBus, rule, pools)
    any(isempty, pools) && return (), ()
    product = Iterators.product(pools...)
    rule == iter.constraint.rule && return product, ()

    split_child = 0
    split_index = 0
    for (i, pool) in enumerate(pools)
        index = get!(iter.last_matches, pool) do
            last_match = findlast(pool) do program
                _check_deadline(iter.bus.deadline)
                HerbConstraints.check_tree(iter.constraint, program)
            end
            something(last_match, 0)
        end
        index == length(pool) && return product, ()
        if index > 0 && split_child == 0
            split_child, split_index = i, index
        end
    end
    split_child == 0 && return (), product

    ranges = [
        i < split_child ? (1:length(pool)) :
        i == split_child ? ((split_index + 1):length(pool)) : (length(pool):length(pool))
        for (i, pool) in enumerate(pools)
    ]
    suffix = Iterators.product((view(pool, range) for (pool, range) in zip(pools, ranges))...)
    first_suffix = first(suffix)
    prefix = Iterators.takewhile(children -> children !== first_suffix, product)
    return prefix, suffix
end

function _defer_contains_product!(iter, type, cost, rule, suffix)
    candidates = Iterators.filter(!isnothing,
        (assemble(iter.bus, rule, CachedRuleNode[children...]) for children in suffix))
    cursor = ResumableBucketCursor(candidates, nothing)
    programs = iter.bus.bank[type][cost]
    push!(get!(() -> DeferredContainsProduct[], iter.deferred, type),
        DeferredContainsProduct(cursor, programs))
    return nothing
end

function _contains_product_candidates(iter, type, cost, rule, pools)
    prefix, suffix = _split_contains_product(iter, rule, pools)
    prefix === () || _flush_deferred!(iter, type)
    candidates = (assemble(iter.bus, rule, CachedRuleNode[children...]) for children in prefix)
    suffix === () && return candidates
    # Record the suffix only when the prefix is exhausted, without walking the suffix.
    return Iterators.flatten((candidates,
        (_defer_contains_product!(iter, type, cost, rule, suffix) for _ in 1:1)))
end

function _resumable_candidates(iter::ContainsCostBasedBus, type::Symbol, cost::Int)
    bus = iter.bus
    grammar = bus.grammar
    return Iterators.filter(!isnothing, (
        program
        for (rule, rule_type) in enumerate(grammar.types) if rule_type == type
        for pools in _resumable_products(identity, iter, grammar.childtypes[rule], cost - bus.rule_costs[rule])
        for program in _contains_product_candidates(iter, type, cost, rule, pools)
    ))
end
