
const HASH_SEED = hash("DON'T PANIC")

function _hash_outputs(outputs)::UInt64
    h = HASH_SEED
    for o in outputs
        h = hash(o, h)
    end
    return h
end

struct CachedRuleNode <: AbstractRuleNode
    rule::Int
    children::Vector{CachedRuleNode}
    outputs::Vector # Preserve each program's concrete output element type.
end



# Implement the AbstractRuleNode interface
HerbCore.isfilled(::CachedRuleNode)::Bool = true
HerbCore.isuniform(::CachedRuleNode)::Bool = true
HerbCore.get_rule(program::CachedRuleNode)::Int = program.rule
HerbCore.get_children(program::CachedRuleNode)::Vector{AbstractRuleNode} = program.children

HerbCore.RuleNode(program::CachedRuleNode) = RuleNode(program.rule, [RuleNode(c) for c in program.children])


struct LazyCostBasedBus
    grammar::AbstractGrammar
    types::Vector{Symbol}
    max_cost::Int
    rule_costs::Vector{Int}
    program_to_outputs
    prune_by_output
    max_output_bytes::Int
    deadline::Float64
    bank::DefaultDict{Symbol,Dict{Int,Vector{CachedRuleNode}}}
    seen_outputs_hashes::DefaultDict{Symbol,Set{UInt64}}
end

LazyCostBasedBus(grammar::AbstractGrammar, types::Vector{Symbol}, max_cost::Int, rule_costs::Vector{Int}, program_to_outputs, prune_by_output; max_output_bytes::Int = 1024^2, deadline::Real = Inf) = LazyCostBasedBus(
    grammar, 
    types, 
    max_cost,
    rule_costs, 
    program_to_outputs, 
    prune_by_output,
    max_output_bytes,
    deadline,
    DefaultDict{Symbol,DefaultDict{Int,Vector{CachedRuleNode}}}(() -> Dict()), 
    DefaultDict{Symbol,Set{UInt64}}(() -> Set{UInt64}()),
)

function get_programs(iter::LazyCostBasedBus, type::Symbol, cost::Int)::Vector{CachedRuleNode}
    _check_deadline(iter.deadline)
    get!(() -> grow(iter, type, cost), iter.bank[type], cost)
end

function compositions(cost::Int, N::Int; deadline::Real = Inf)
    _check_deadline(deadline)
    cost < 0 && return []
    N == 0 && return [[]]

    if N == 1
        return [[cost]]
    end

    result = Vector{Vector{Int}}()

    for x in 0:cost
        for tail in compositions(cost - x, N - 1; deadline=deadline)
            push!(result, [x; tail])
        end
    end

    return result
end

function program_combinations(iter::LazyCostBasedBus, types::Vector{Symbol}, total_cost::Int)
    combinations = []
    for costs in compositions(total_cost, length(types); deadline=iter.deadline)
        pools = [get_programs(iter, type, cost) for (type, cost) in zip(types, costs)]
        for children in Iterators.product(pools...)
            _check_deadline(iter.deadline)
            push!(combinations, children)
        end
    end
    return combinations
end

function assemble(iter::LazyCostBasedBus, rule::Int, children::Vector{CachedRuleNode})
    _check_deadline(iter.deadline)
    type = iter.grammar.types[rule]
    child_outputs = [c.outputs for c in children]
    outputs = iter.program_to_outputs(rule, child_outputs)
    _check_deadline(iter.deadline)
    # Check the complete output vector before hashing or caching it.
    iter.max_output_bytes != typemax(Int) && Base.summarysize(outputs) > iter.max_output_bytes && return nothing
    any(iter.prune_by_output, outputs) && return nothing
    outputs_hash = _hash_outputs(outputs)
    outputs_hash in iter.seen_outputs_hashes[type] && return nothing

    push!(iter.seen_outputs_hashes[type], outputs_hash)
    return CachedRuleNode(rule, children, outputs)
end

function grow(iter::LazyCostBasedBus, type::Symbol, cost::Int)
    g = iter.grammar

    collect(Iterators.filter(!isnothing,
        assemble(iter, rule, Vector{CachedRuleNode}(collect(children)))
        for (rule, rule_type) in enumerate(g.types) if rule_type == type
        for children in program_combinations(iter, g.childtypes[rule], cost - iter.rule_costs[rule])
    ))
end

function _satisfies_constraints(grammar, prog)
    isempty(grammar.constraints) && return true
    all(HerbConstraints.check_tree(c, prog) for c in grammar.constraints)
end

# Points at last program returned
mutable struct LazyCostBasedBusState
    program_index::Int
    type_index::Int
    cost::Int
end

Base.iterate(iter::LazyCostBasedBus) = Base.iterate(iter, LazyCostBasedBusState(0, 1, 0))


function Base.iterate(iter::LazyCostBasedBus, state::LazyCostBasedBusState)
    # Obtain programs of previous type and cost
    programs = get_programs(iter, iter.types[state.type_index], state.cost)
    
    # Advance pointers to next program
    while true
        _check_deadline(iter.deadline)
        state.program_index += 1
        state.program_index > length(programs) && (state.program_index = 1; state.type_index += 1)
        state.type_index > length(iter.types) && (state.type_index = 1; state.cost += 1)
        state.cost > iter.max_cost && return nothing

        programs = get_programs(iter, iter.types[state.type_index], state.cost)
        state.program_index > length(programs) && continue
        program = programs[state.program_index]
        !_satisfies_constraints(iter.grammar, program) && continue

        return program, state
    end
end
