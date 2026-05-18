
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
    outputs::Vector{Any}
end



# Implement the AbstractRuleNode interface
HerbCore.isfilled(::CachedRuleNode)::Bool = true
HerbCore.isuniform(::CachedRuleNode)::Bool = true
HerbCore.get_rule(program::CachedRuleNode)::Int = program.rule
HerbCore.get_children(program::CachedRuleNode)::Vector{AbstractRuleNode} = program.children

HerbCore.RuleNode(program::CachedRuleNode) = RuleNode(program.rule, [RuleNode(c) for c in program.children])


struct LazySizeBasedBus
    grammar::AbstractGrammar
    types::Vector{Symbol}
    max_size::Int
    program_to_outputs
    bank::DefaultDict{Symbol,Dict{Int,Vector{CachedRuleNode}}}
    seen_outputs_hashes::DefaultDict{Symbol,Set{UInt64}}
    max_bank_size::Union{Nothing,Int}
    limit_bank_size_by::Union{Nothing,Function}
end

LazySizeBasedBus(grammar::AbstractGrammar, types::Vector{Symbol}, max_size::Int, program_to_outputs) = LazySizeBasedBus(grammar, types, max_size, program_to_outputs, DefaultDict{Symbol,DefaultDict{Int,Vector{CachedRuleNode}}}(() -> Dict()), DefaultDict{Symbol,Set{UInt64}}(() -> Set{UInt64}()), nothing, nothing)
LazySizeBasedBus(grammar::AbstractGrammar, types::Vector{Symbol}, max_size::Int, program_to_outputs, max_bank_size::Int, limit_bank_size_by) = LazySizeBasedBus(grammar, types, max_size, program_to_outputs, DefaultDict{Symbol,DefaultDict{Int,Vector{CachedRuleNode}}}(() -> Dict()), DefaultDict{Symbol,Set{UInt64}}(() -> Set{UInt64}()), max_bank_size, limit_bank_size_by)

function get_programs(iter::LazySizeBasedBus, type::Symbol, size::Int)::Vector{CachedRuleNode}
    get!(() -> grow(iter, type, size), iter.bank[type], size)
end

function compositions(size::Int, N::Int)
    N == 0 && size == 0 && return [[]]
    (size == 0 || N == 0) && return []
    N == 1 && return [[size]]

    result = Vector{Vector{Int}}()

    for first in 1:(size - N + 1)
        for rest in compositions(size - first, N - 1)
            push!(result, [first; rest])
        end
    end

    return result
end

function program_combinations(iter::LazySizeBasedBus, types::Vector{Symbol}, total_size::Int)
    Iterators.flatten(
        Iterators.product([get_programs(iter, type, cost) for (type, cost) in zip(types, costs)]...)
        for costs in compositions(total_size, length(types))
    )
end

function assemble(iter::LazySizeBasedBus, rule::Int, children::Vector{CachedRuleNode})
    type = iter.grammar.types[rule]
    child_outputs = Vector{Any}[c.outputs for c in children]
    outputs = iter.program_to_outputs(rule, child_outputs)
    outputs_hash = _hash_outputs(outputs)

    any(isnothing, outputs) && return nothing
    outputs_hash in iter.seen_outputs_hashes[type] && return nothing

    push!(iter.seen_outputs_hashes[type], outputs_hash)
    return CachedRuleNode(rule, children, outputs)
end

function grow(iter::LazySizeBasedBus, type::Symbol, size::Int)
    g = iter.grammar

    res = collect(Iterators.filter(!isnothing,
        assemble(iter, rule, Vector{CachedRuleNode}(collect(children)))
        for (rule, rule_type) in enumerate(g.types) if rule_type == type
        for children in program_combinations(iter, g.childtypes[rule], size - 1)
    ))

    isnothing(iter.limit_bank_size_by) && return res
    sort!(res, by=iter.limit_bank_size_by)
    return res[1:min(iter.max_bank_size, end)]
end

function _satisfies_constraints(grammar, prog)
    isempty(grammar.constraints) && return true
    all(HerbConstraints.check_tree(c, prog) for c in grammar.constraints)
end

# Points at last program returned
mutable struct LazySizeBasedBusState
    program_index::Int
    type_index::Int
    size::Int
end

Base.iterate(iter::LazySizeBasedBus) = Base.iterate(iter, LazySizeBasedBusState(0, 1, 1))


function Base.iterate(iter::LazySizeBasedBus, state::LazySizeBasedBusState)
    # Obtain programs of previous type and size
    programs = get_programs(iter, iter.types[state.type_index], state.size)
    
    # Advance pointers to next program
    while true
        state.program_index += 1
        state.program_index > length(programs) && (state.program_index = 1; state.type_index += 1)
        state.type_index > length(iter.types) && (state.type_index = 1; state.size += 1)
        state.size > iter.max_size && return nothing

        programs = get_programs(iter, iter.types[state.type_index], state.size)
        state.program_index > length(programs) && continue
        program = programs[state.program_index]
        !_satisfies_constraints(iter.grammar, program) && continue

        return program, state
    end
end