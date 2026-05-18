
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


struct LazyDepthBasedBus
    grammar::AbstractGrammar
    types::Vector{Symbol}
    max_depth::Int
    program_to_outputs
    bank::DefaultDict{Symbol,Dict{Int,Vector{CachedRuleNode}}}
    seen_outputs_hashes::DefaultDict{Symbol,Set{UInt64}}
end

LazyDepthBasedBus(grammar::AbstractGrammar, types::Vector{Symbol}, max_depth::Int, program_to_outputs) = LazyDepthBasedBus(grammar, types, max_depth, program_to_outputs, DefaultDict{Symbol,DefaultDict{Int,Vector{CachedRuleNode}}}(() -> Dict()), DefaultDict{Symbol,Set{UInt64}}(() -> Set{UInt64}()))

function get_programs(iter::LazyDepthBasedBus, type::Symbol, depth::Int)::Vector{CachedRuleNode}
    get!(() -> grow(iter, type, depth), iter.bank[type], depth)
end

function compositions(depth::Int, N::Int)
    N == 0 && depth == 0 && return [[]]
    (depth == 0 || N == 0) && return []

    res = []

    for n in 1:N
        choices = [i == n ? [depth] : 1:depth for i in 1:N]
        append!(res, collect(Iterators.product(choices...)))
    end

    return res
end

function program_combinations(iter::LazyDepthBasedBus, types::Vector{Symbol}, total_depth::Int)
    Iterators.flatten(
        Iterators.product([get_programs(iter, type, cost) for (type, cost) in zip(types, costs)]...)
        for costs in compositions(total_depth, length(types))
    )
end

function assemble(iter::LazyDepthBasedBus, rule::Int, children::Vector{CachedRuleNode})
    type = iter.grammar.types[rule]
    child_outputs = Vector{Any}[c.outputs for c in children]
    outputs = iter.program_to_outputs(rule, child_outputs)
    outputs_hash = _hash_outputs(outputs)

    any(isnothing, outputs) && return nothing
    outputs_hash in iter.seen_outputs_hashes[type] && return nothing

    push!(iter.seen_outputs_hashes[type], outputs_hash)
    return CachedRuleNode(rule, children, outputs)
end

function grow(iter::LazyDepthBasedBus, type::Symbol, depth::Int)
    g = iter.grammar

    collect(Iterators.filter(!isnothing,
        assemble(iter, rule, Vector{CachedRuleNode}(collect(children)))
        for (rule, rule_type) in enumerate(g.types) if rule_type == type
        for children in program_combinations(iter, g.childtypes[rule], depth - 1)
    ))
end

function _satisfies_constraints(grammar, prog)
    isempty(grammar.constraints) && return true
    all(HerbConstraints.check_tree(c, prog) for c in grammar.constraints)
end

# Points at last program returned
mutable struct LazyDepthBasedBusState
    program_index::Int
    type_index::Int
    depth::Int
end

Base.iterate(iter::LazyDepthBasedBus) = Base.iterate(iter, LazyDepthBasedBusState(0, 1, 1))


function Base.iterate(iter::LazyDepthBasedBus, state::LazyDepthBasedBusState)
    # Obtain programs of previous type and depth
    programs = get_programs(iter, iter.types[state.type_index], state.depth)
    
    # Advance pointers to next program
    while true
        state.program_index += 1
        state.program_index > length(programs) && (state.program_index = 1; state.type_index += 1)
        state.type_index > length(iter.types) && (state.type_index = 1; state.depth += 1)
        state.depth > iter.max_depth && return nothing

        programs = get_programs(iter, iter.types[state.type_index], state.depth)
        state.program_index > length(programs) && continue
        program = programs[state.program_index]
        !_satisfies_constraints(iter.grammar, program) && continue

        return program, state
    end
end