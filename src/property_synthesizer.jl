
struct Property
    program::AbstractRuleNode
    target_values::Vector
    agreement::Int
    enumeration_index::Int
end

const DEFAULT_MAX_PROPERTY_EVALUATIONS = 10_000

struct PropertyEvaluationLimit <: Exception end

struct PropertyCandidates
    bus::ResumableCostBasedBus
    remaining::Base.RefValue{Int}
    budget::Int
end

Base.IteratorSize(::Type{PropertyCandidates}) = Base.SizeUnknown()
Base.eltype(::Type{PropertyCandidates}) = CachedRuleNode

function Base.iterate(candidates::PropertyCandidates, state...)
    candidates.remaining[] == 0 && return nothing
    try
        return iterate(candidates.bus, state...)
    catch err
        err isa PropertyEvaluationLimit || rethrow()
        return nothing
    end
end

# An unbounded cost scan needs at least one type with a finite expression.
function _has_property_expressions(grammar, property_types, deadline)
    productive = Set{Symbol}()
    while true
        _check_deadline(deadline)
        previous_size = length(productive)
        for (type, children) in zip(grammar.types, grammar.childtypes)
            isnothing(type) && continue
            all(in(productive), children) && push!(productive, type)
        end
        any(in(productive), property_types) && return true
        length(productive) == previous_size && return false
    end
end

function _property_candidates(;
    benchmark,
    problem,
    grammar::AbstractGrammar,
    local_optimum_outputs::AbstractVector{<:AbstractVector},
    property_types::Vector{Symbol},
    max_cost::Union{Nothing,Int} = nothing,
    max_property_evaluations::Int = isnothing(max_cost) ? DEFAULT_MAX_PROPERTY_EVALUATIONS : typemax(Int),
    rule_costs::Vector{Int},
    interpreter = nothing,
    prune_node_by_output::Function = _ -> false,
    max_output_bytes::Int = 21 * 1024^2,
    deadline::Real = Inf,
    # Shared across property searches; updated before interpretation, including pruned candidates.
    properties_enumerated::Base.RefValue{Int} = Ref(0),
)
    max_property_evaluations >= 0 || throw(ArgumentError("max_property_evaluations must be nonnegative"))
    _check_deadline(deadline)
    max_property_evaluations == 0 && return ()
    isnothing(max_cost) && !_has_property_expressions(grammar, property_types, deadline) && return ()
    target_outputs = [io.out for io in problem.spec]

    interp = isnothing(interpreter) ?
        HerbInterpret.make_output_interpreter(grammar, target_module=benchmark, cache_module=benchmark) : interpreter
    specs = [(new_in = copy(io.in); new_in[:_arg_out] = y; new_in) for (io, y) in zip(Iterators.cycle(problem.spec), [target_outputs; local_optimum_outputs...])]
    remaining = Ref(max_property_evaluations)
    interp_all = (rule, os) -> begin
        remaining[] == 0 && throw(PropertyEvaluationLimit())
        remaining[] -= 1
        properties_enumerated[] += 1
        interp(rule, os, specs)
    end

    bus = ResumableCostBasedBus(
        grammar, 
        property_types,
        something(max_cost, typemax(Int)),
        rule_costs,
        interp_all,
        prune_node_by_output;
        max_output_bytes = max_output_bytes,
        deadline = deadline,
    )
    return PropertyCandidates(bus, remaining, max_property_evaluations)
end

_property_enumeration_index(candidates::PropertyCandidates) = candidates.budget - candidates.remaining[]

function _property_values(property, num_examples)
    target_values = property.outputs[1:num_examples]
    sample_values = @view property.outputs[num_examples+1:end]
    return target_values, Iterators.partition(sample_values, num_examples)
end

"""Find the property with the lowest positive agreement, stopping early at the threshold.

Agreement counts local optima whose property outputs match the target on every
example. Return the first property with agreement in `1:agreement_threshold`,
or the best positive match found within the search budget. Return
`nothing` if no property has positive agreement. The threshold defaults to 1.
Each call uses fresh task outputs and enumeration state.

`max_property_evaluations` limits interpreter calls per search, including
intermediate, pruned and duplicate candidates. The default is 10,000.
An explicit `max_cost` supports cost-bounded runs, with an evaluation limit
only when supplied.

An optional `interpreter` may be reused only for the same unchanged grammar and
benchmark module. It caches generated code, not inputs, outputs or search state.
"""
function find_property!(; problem, agreement_threshold::Int = 1, deadline::Real = Inf, kwargs...)
    agreement_threshold >= 1 || throw(ArgumentError("agreement_threshold must be positive"))
    properties = _property_candidates(; problem, deadline, kwargs...)
    best_property = nothing
    best_target_values = nothing
    best_agreement = typemax(Int)
    best_index = 0

    for property in properties
        _check_deadline(deadline)
        target_values, local_property_values = _property_values(property, length(problem.spec))

        agreement = count(values == target_values for values in local_property_values)

        if agreement > 0 && agreement < best_agreement
            best_property = property
            best_target_values = target_values
            best_agreement = agreement
            best_index = _property_enumeration_index(properties)

            agreement <= agreement_threshold && break
        end
    end

    isnothing(best_property) && return nothing
    return Property(RuleNode(best_property), best_target_values, best_agreement, best_index)
end
