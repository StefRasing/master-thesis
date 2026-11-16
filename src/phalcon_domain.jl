# Enumerate syntax across the shared grammar. Output deduplication on one
# task could discard a property with a different score on another task.
function _foreach_domain_property(visit, grammar, types, costs, max_cost; deadline=Inf)
    bank = Dict{Tuple{Symbol,Int},Vector{RuleNode}}()
    active = Set{Tuple{Symbol,Int}}()
    function generate(emit, type, cost)
        _check_deadline(deadline)
        for rule in eachindex(grammar.rules)
            grammar.types[rule] == type || continue
            remaining = cost - costs[rule]
            remaining < 0 && continue
            children_types = grammar.childtypes[rule]
            isempty(children_types) && remaining != 0 && continue
            for allocation in compositions(remaining, length(children_types); deadline)
                pools = [cached(t, c) for (t, c) in zip(children_types, allocation)]
                for children in Iterators.product(pools...)
                    _check_deadline(deadline)
                    emit(RuleNode(rule, RuleNode[children...]))
                end
            end
        end
    end
    function cached(type, cost)
        key = (type, cost)
        get!(bank, key) do
            key in active && throw(ArgumentError("zero-cost cycle in property grammar at $type"))
            push!(active, key)
            nodes = RuleNode[]
            generate(p -> push!(nodes, p), type, cost)
            delete!(active, key)
            nodes
        end
    end
    output_rules = findall(==(:_arg_out), grammar.rules)
    isempty(output_rules) && return
    contains_output(node) = get_rule(node) in output_rules || any(contains_output, get_children(node))

    # Acyclic grammars can exhaust before the property limit. Stop at the
    # largest attainable cost instead of scanning empty buckets indefinitely.
    bounds = Dict{Symbol,Int}()
    function cost_bound(type)
        get!(bounds, type, typemax(Int))
        maximum_cost = 0
        for rule in eachindex(grammar.rules)
            grammar.types[rule] == type || continue
            bound = costs[rule]
            for child in grammar.childtypes[rule]
                child_bound = haskey(bounds, child) ? bounds[child] : cost_bound(child)
                bound += min(child_bound, typemax(Int) - bound)
            end
            maximum_cost = max(maximum_cost, bound)
        end
        return bounds[type] = maximum_cost
    end
    stop_cost = min(max_cost, maximum((cost_bound(type) for type in types); init=0))
    for cost in 0:stop_cost, type in types
        generate(type, cost) do program
            contains_output(program) && _satisfies_constraints(grammar, program) &&
                visit(program, type, cost)
        end
    end
    return nothing
end

# Cache only reusable children, not every root property. RuleNode keys compare
# structurally; tasks have independent contexts and are part of the key.
mutable struct DomainPropertyOutputCache
    values::Dict{Tuple{Int,RuleNode},Vector}
    bytes::Int
    limit::Int
end
DomainPropertyOutputCache(limit) = DomainPropertyOutputCache(Dict{Tuple{Int,RuleNode},Vector}(), 0, limit)

function _domain_output_bytes_bound(values)
    remaining, _ = _output_size_budget(values, typemax(Int), typemax(Int), 8)
    return remaining >= 0 ? typemax(Int) - remaining : Base.summarysize(values)
end

function _evaluate_domain_property(interpreter, program, context, cache=nothing, task_index=0; retain=false)
    key = (task_index, program)
    if !isnothing(cache) && haskey(cache.values, key)
        return cache.values[key]
    end
    children = [_evaluate_domain_property(interpreter, child, context, cache, task_index; retain=true)
        for child in get_children(program)]
    values = interpreter(get_rule(program), children, context)
    if retain && !isnothing(cache) && cache.limit > 0
        bytes = _domain_output_bytes_bound(values)
        if bytes <= cache.limit
            if bytes > cache.limit - cache.bytes
                empty!(cache.values)
                cache.bytes = 0
            end
            cache.values[key] = values
            cache.bytes += bytes
        end
    end
    return values
end

# SyGuS strings includes integer and Boolean return types. A property may
# call a primitive that has no method for a particular example's output type.
function _interpret_domain_rule(interpreter, rule, children, context)
    try
        return interpreter(rule, children, context)
    catch err
        err isa Union{MethodError,TypeError} || rethrow()
        context isa AbstractVector || return nothing
        return [_interpret_domain_rule(interpreter, rule, [child[i] for child in children], context[i])
            for i in eachindex(context)]
    end
end

function _domain_property_input(ex, y)
    input = Dict{Symbol,Any}(ex.in)
    input[:_arg_out] = y
    return input
end

"""Count whole-program acceptances: the property must match on EVERY I/O example."""
function _domain_agreement(values, examples::Int, programs::Int; pattern=nothing, offset=0)
    length(values) == examples * (programs + 1) || throw(DimensionMismatch("property output batch"))
    target = @view values[1:examples]
    any(isnothing, target) && return nothing
    return count(1:programs) do index
        candidate = @view values[index*examples+1:(index+1)*examples]
        agrees = !any(isnothing, candidate) && candidate == target
        isnothing(pattern) || (pattern[offset + index] = agrees)
        return agrees
    end
end

function _domain_score!(pattern, program, tasks, contexts, sample_sizes, interpret, cache,
        max_output_bytes, prune_node_by_output, deadline)
    score = 0
    offset = 0
    zero_agreements = 0
    max_zero_agreements = length(tasks) ÷ 2
    for (i, (task, context)) in enumerate(zip(tasks, contexts))
        _check_deadline(deadline)
        values = _evaluate_domain_property(interpret, program, context, cache, i)
        _within_output_limit(values, max_output_bytes) || return 0
        agreement = _domain_agreement(values, length(task.problem.spec), sample_sizes[i]; pattern, offset)
        isnothing(agreement) && return 0
        offset += sample_sizes[i]
        zero_agreements += iszero(agreement)
        zero_agreements > max_zero_agreements && return 0
        any(prune_node_by_output, values) && return 0
        score += agreement
    end
    return score
end

struct DomainPropertyLimit <: Exception end
struct DomainProgramLimit <: Exception end

function _sample_domain_programs(task, benchmark, rule_cost_func, population_size,
        max_program_cost, max_output_bytes, deadline; interpreters=Dict(), max_program_evaluations=100_000)
    grammar, problem = task.grammar, task.problem
    interpret = get!(interpreters, (benchmark, grammar.types, grammar.rules, grammar.childtypes)) do
        HerbInterpret.make_output_interpreter(grammar; target_module=benchmark, cache_module=benchmark)
    end
    evaluations = 0
    function evaluate(rule, children)
        evaluations == max_program_evaluations && throw(DomainProgramLimit())
        evaluations += 1
        return interpret(rule, children, problem.spec)
    end
    bus = ResumableCostBasedBus(grammar, [:Start], max_program_cost,
        Int[rule_cost_func(r) for r in grammar.rules], evaluate, isnothing;
        max_output_bytes, deadline)
    outputs = Vector[]
    target = [ex.out for ex in problem.spec]
    try
        for program in bus
            program.outputs == target && continue
            push!(outputs, program.outputs)
            length(outputs) == population_size && break
        end
    catch err
        err isa DomainProgramLimit || rethrow()
    end
    return outputs
end

"""
    rank_domain_properties(tasks; benchmark, grammar, property_types, rule_cost_func, ...)

Build a reusable ranking for tasks with a shared property grammar. Sample the
first 20 behaviorally distinct non-solutions per task in program-cost order.
Rank the first 10,000 syntactic properties containing `_arg_out` by ascending
total agreement. A program agrees only if every example matches. Discard a
property if more than half of the tasks have zero agreement. Keep the first
property for each agreement pattern across all sampled programs. Ties retain
enumeration order.
"""
function rank_domain_properties(tasks;
    benchmark::Module, grammar::AbstractGrammar, property_types::Vector{Symbol},
    rule_cost_func::Function, population_size::Int=20, max_property_evaluations::Int=DEFAULT_MAX_PROPERTY_EVALUATIONS,
    max_program_cost::Int=6, max_program_evaluations::Int=100_000, max_property_cost::Union{Nothing,Int}=nothing,
    prune_node_by_output::Function=_ -> false, max_output_bytes::Int=21 * 1024^2,
    cache_bytes::Int=128 * 1024^2, timeout::Real=Inf, program_interpreters=Dict(),
)
    isempty(tasks) && throw(ArgumentError("domain ranking requires at least one task"))
    all(t -> !isempty(t.problem.spec), tasks) || throw(ArgumentError("domain tasks need examples"))
    population_size > 0 || throw(ArgumentError("population_size must be positive"))
    max_program_cost >= 0 || throw(ArgumentError("max_program_cost must be nonnegative"))
    max_program_evaluations > 0 || throw(ArgumentError("max_program_evaluations must be positive"))
    max_property_evaluations >= 0 || throw(ArgumentError("max_property_evaluations must be nonnegative"))
    deadline = _search_time() + timeout
    start = time()
    ranked = Tuple{RuleNode,Int,Int}[]
    sample_sizes = Int[]
    enumerated = 0
    interpret = nothing
    if max_property_evaluations > 0
        contexts = map(tasks) do task
            _check_deadline(deadline)
            sample_size = min(population_size, get(task, :sample_size_limit, population_size))
            outputs = _sample_domain_programs(task, benchmark, rule_cost_func, sample_size,
                max_program_cost, max_output_bytes, deadline; interpreters=program_interpreters,
                max_program_evaluations)
            push!(sample_sizes, length(outputs))
            problem = task.problem
            targets = [ex.out for ex in problem.spec]
            return [_domain_property_input(ex, y)
                for values in [Vector[targets]; outputs] for (ex, y) in zip(problem.spec, values)]
        end
        output_interpreter = HerbInterpret.make_output_interpreter(grammar;
            target_module=benchmark, cache_module=benchmark)
        interpret = (rule, children, context) -> _interpret_domain_rule(output_interpreter, rule, children, context)
        cache = DomainPropertyOutputCache(cache_bytes)
        costs = Int[rule_cost_func(r) for r in grammar.rules]
        all(>=(0), costs) || throw(ArgumentError("property rule costs must be nonnegative"))
        pattern = falses(sum(sample_sizes))
        seen_agreements = Set{BitVector}()
        try
            _foreach_domain_property(grammar, property_types, costs, something(max_property_cost, typemax(Int)); deadline) do program, _, _
                enumerated += 1
                score = _domain_score!(pattern, program, tasks, contexts, sample_sizes,
                    interpret, cache, max_output_bytes, prune_node_by_output, deadline)
                if score > 0 && !(pattern in seen_agreements)
                    push!(seen_agreements, copy(pattern))
                    push!(ranked, (program, score, enumerated))
                end
                enumerated == max_property_evaluations && throw(DomainPropertyLimit())
            end
        catch err
            err isa DomainPropertyLimit || rethrow()
        end
        sort!(ranked; by=entry -> (entry[2], entry[3]))
    end
    return (; grammar, benchmark, interpret, ranked, enumerated, sample_sizes, duration=time() - start)
end

"""
    phalcon_domain(; iterator, ranking, max_number_of_properties=20, timeout=Inf)

Run a genetic search with a fixed prefix of a precomputed domain ranking.
Compute property targets on the current training examples. No property
enumeration or reselection takes place during the trial.
"""
function phalcon_domain(; iterator::GeneticIterator, ranking,
    max_number_of_properties::Int=20, timeout::Real=Inf)
    max_number_of_properties >= 0 || throw(ArgumentError("max_number_of_properties must be nonnegative"))
    iterator.benchmark === ranking.benchmark || throw(ArgumentError("ranking benchmark must match iterator"))
    start = time()
    deadline = _search_time() + timeout
    properties = Property[]
    solution = nothing
    try
        _check_deadline(deadline)
        if max_number_of_properties > 0 && !isempty(ranking.ranked)
            property_interp = (program, ex, y) ->
                _evaluate_domain_property(ranking.interpret, program, _domain_property_input(ex, y))
            for (program, score, index) in Iterators.take(ranking.ranked, max_number_of_properties)
                _check_deadline(deadline)
                values = [property_interp(program, ex, ex.out) for ex in iterator.problem.spec]
                push!(properties, Property(program, values, score, index))
            end
            iterator.cost = _property_cost(iterator.problem, properties, property_interp)
        end
        initialize!(iterator; deadline)
        if !isempty(iterator.population) && (first(iterator.population).cost == -Inf || _has_batch_parents(iterator))
            solution = find_solution(iterator; deadline)
        end
    catch err
        err isa SearchTimeout || rethrow()
    end
    return solution, _phalcon_stats(iterator, solution, start, 0, ranking.grammar,
        properties, Number[], [time() - start], Float64[])
end
