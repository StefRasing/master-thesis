mutable struct ResumableBucketCursor{I}
    candidates::I
    state::Union{Nothing,Some,Missing}
end

abstract type AbstractResumableCostBus end

"""
    ResumableCostBasedBus(grammar, types, max_cost, rule_costs, program_to_outputs,
                          prune_by_output; max_output_bytes=1024^2, deadline=Inf)

Enumerate programs in the order of `LazyCostBasedBus`, suspending evaluation
of the current bucket after each yield. Child pools are completed in the
original discovery order to preserve first-seen output deduplication.
"""
struct ResumableCostBasedBus <: AbstractResumableCostBus
    bus::LazyCostBasedBus
    cursors::Dict{Tuple{Symbol,Int},ResumableBucketCursor}
end

function ResumableCostBasedBus(grammar::AbstractGrammar, types::Vector{Symbol}, max_cost::Int,
                               rule_costs::Vector{Int}, program_to_outputs, prune_by_output;
                               max_output_bytes::Int = 1024^2, deadline::Real = Inf)
    bus = LazyCostBasedBus(grammar, types, max_cost, rule_costs, program_to_outputs,
        prune_by_output; max_output_bytes, deadline)
    return ResumableCostBasedBus(bus, Dict{Tuple{Symbol,Int},ResumableBucketCursor}())
end

function _resumable_products(make_product, iter, types, total_cost)
    # Discover every pool for this rule before assembling its first parent.
    # Only the product iterators are stored, even for very large pools.
    return [
        make_product([get_programs(iter, type, cost) for (type, cost) in zip(types, costs)])
        for costs in compositions(total_cost, length(types); deadline=iter.bus.deadline)
    ]
end

function _resumable_candidates(iter::ResumableCostBasedBus, type::Symbol, cost::Int)
    bus = iter.bus
    grammar = bus.grammar
    return Iterators.filter(!isnothing, (
        assemble(bus, rule, CachedRuleNode[children...])
        for (rule, rule_type) in enumerate(grammar.types) if rule_type == type
        for children in Iterators.flatten(_resumable_products(
            pools -> Iterators.product(pools...), iter, grammar.childtypes[rule], cost - bus.rule_costs[rule]))
    ))
end

function _resumable_bucket(iter::AbstractResumableCostBus, key::Tuple{Symbol,Int})
    type, cost = key
    return get!(iter.bus.bank[type], cost) do
        iter.cursors[key] = ResumableBucketCursor(_resumable_candidates(iter, type, cost), nothing)
        CachedRuleNode[]
    end
end

function _advance_bucket!(iter::AbstractResumableCostBus, key, programs)::Union{Nothing,CachedRuleNode}
    _check_deadline(iter.bus.deadline)
    cursor = get(iter.cursors, key, nothing)
    cursor === nothing && return nothing
    program = _advance_cursor!(cursor, programs)
    program === nothing && delete!(iter.cursors, key)
    return program
end

function _advance_cursor!(cursor::ResumableBucketCursor, programs)
    state = cursor.state
    state === missing && return nothing
    next = state === nothing ? iterate(cursor.candidates) : iterate(cursor.candidates, something(state))
    if next === nothing
        cursor.state = missing
        return nothing
    end
    program, next_state = next
    push!(programs, program)
    cursor.state = Some(next_state)
    return program
end

_flush_deferred!(::AbstractResumableCostBus, ::Symbol) = nothing
_finish_cost!(::AbstractResumableCostBus, ::Int) = nothing

function get_programs(iter::AbstractResumableCostBus, type::Symbol, cost::Int)::Vector{CachedRuleNode}
    _check_deadline(iter.bus.deadline)
    _flush_deferred!(iter, type)
    key = (type, cost)
    programs = _resumable_bucket(iter, key)
    while _advance_bucket!(iter, key, programs) !== nothing
    end
    _flush_deferred!(iter, type)
    return programs
end

Base.IteratorSize(::Type{<:AbstractResumableCostBus}) = Base.SizeUnknown()
Base.eltype(::Type{<:AbstractResumableCostBus}) = CachedRuleNode

function Base.iterate(iter::AbstractResumableCostBus, state::NTuple{3,Int} = (0, 1, 1))
    bus = iter.bus
    cost, type_index, program_index = state
    while cost <= bus.max_cost && !isempty(bus.types)
        _check_deadline(bus.deadline)
        key = (bus.types[type_index], cost)
        programs = _resumable_bucket(iter, key)
        if program_index > length(programs)
            _advance_bucket!(iter, key, programs)
        end
        if program_index > length(programs)
            program_index = 1
            type_index += 1
            if type_index > length(bus.types)
                cost == bus.max_cost && return nothing
                _finish_cost!(iter, cost)
                type_index = 1
                cost += 1
            end
        else
            program = programs[program_index]
            program_index += 1
            _satisfies_constraints(bus.grammar, program) && return program, (cost, type_index, program_index)
        end
    end
    return nothing
end
