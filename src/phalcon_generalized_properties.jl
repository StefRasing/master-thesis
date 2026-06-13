abstract type AbstractPhalconGeneralizedProperties <: ProgramIterator end

mutable struct Property
    program::AbstractRuleNode
    distance::Function
end


@programiterator mutable PhalconGeneralizedProperties(
    problem = nothing,
    
    pool_size::Int = 0,
    max_extension_depth::Int = 1,
    max_extension_size::Int = 1,

    grammar_to_property_grammar::Function = identity,
    max_property_depth::Int = 4,
    max_property_size::Int = 6,
    max_number_of_properties::Int = typemax(Int),

    increase_percentage_threshold::Float64 = 1.0,
    normalized_distance_functions::Dict{Symbol,Function}=Dict([]),
    
    pool::Vector{PoolEntry} = PoolEntry[],
    extensions::DefaultDict{Symbol,Vector{AbstractRuleNode}} = DefaultDict{Symbol,Vector{AbstractRuleNode}}(() -> AbstractRuleNode[]),
    candidate_properties::Vector{Property} = Property[],
    selected_properties::Vector{Property} = Property[],

    benchmark = nothing,
    property_grammar = nothing,
    interpreter = nothing,
    property_interpreter = nothing,

    programs_evaluated::Int = 0,
    properties_evaluated::Int = 0,
) <: AbstractPhalconGeneralizedProperties

function heuristic_cost(iter::PhalconGeneralizedProperties, program::AbstractRuleNode)::Number
    spec = iter.problem.spec

    if isnothing(program._val) || length(program._val) == 0
        program._val = [iter.interpreter(program, io.in) for io in spec]
    end

    outputs = program._val

    any(isnothing, outputs) && return typemax(Int)
    all(output == io.out for (output, io) in zip(outputs, spec)) && return -1
    isempty(iter.selected_properties) && return 0

    return sum(
        property.distance([iter.property_interpreter(property.program, (io.in[:_arg_out] = output; io.in)) for (output, io) in zip(program._val, iter.problem.spec)]) 
        for property in iter.selected_properties)
end


"""
    Base.add_to_pool!(iter::AbstractBeamIterator, beam_entry::BeamEntry)

Adds a program to the pool, ensuring that the pool size is not exceeded and only the best programs are kept.
"""
function add_to_pool!(iter::PhalconGeneralizedProperties, program::AbstractRuleNode, parent=nothing)    
    if any([!check_tree(constraint, program) for constraint in iter.solver.grammar.constraints])
        return nothing
    end
    
    cost = heuristic_cost(iter, program)
    pool_entry = PoolEntry(program, cost, depth(program), length(program); parent = parent)

    # If the cost is infinity, skip the program
    if cost == Inf
        return nothing
    end

    # If the beam is full and the new entry has a higher cost than the worst in the beam, we can abort
    if length(iter.pool) >= iter.pool_size && pool_entry >= iter.pool[end]
        return nothing
    end

    #= Otherwise, add the program to the beam
    
    The main difficulty is checking whether a equal (or equivalent program with observation_equivalance) exists in the beam.
    For this, we only wish to check the programs (or outputs) for beam entries that have the same cost.
    
    For this we find the range of equal costs: 
     - The last index in the array that has a lower cost
     - The first index in the array that has a higher cost
    =#
    first_index = searchsortedfirst([e.cost for e in iter.pool], pool_entry.cost)
    last_index = searchsortedlast([e.cost for e in iter.pool], pool_entry.cost)

    # If last_index > first_index, there is no entry with the same cost, and this step can be skipped
    if first_index <= last_index
        
        # To avoid duplicates, we check every beam entry in this range and see if the program or outputs are already present
        for i in first_index:last_index

            # Check if the programs are equal; abort if so
            if iter.pool[i].program == program
                return nothing
            end

            # If an interpreter is supplied and we have observation_equivalance, check if the outputs are equal; keep the shortest program in that case
            if iter.pool[i].program._val == program._val
                if pool_entry < iter.pool[i]
                    iter.pool[i] = pool_entry
                end

                return nothing
            end
        end
    end

    index = searchsortedlast(iter.pool, pool_entry)

    # If the entry made it through all the checks above, insert it
    insert!(iter.pool, index + 1, pool_entry)

    # If that exceeded the beam size, pop the worst entry (located at the end)
    if length(iter.pool) > iter.pool_size
        pop!(iter.pool)
    end

    return nothing
end

"""
    initialize!(iter::AbstractBeamIterator)

Initializes the iterator by creating all extensions and setting the first beam.
"""
function initialize!(iter::PhalconGeneralizedProperties)
    # ---------------------------
    #   1. Setup fields
    # ---------------------------

    grammar = iter.solver.grammar
    iter.property_grammar = grammar_to_property_grammar(grammar)
    
    interp = HerbInterpret.make_interpreter(grammar, target_module=iter.benchmark, cache_module=iter.benchmark)
    iter.interpreter = (p,x) -> (iter.programs_evaluated += 1; interp(p,x))
    prop_interp = HerbInterpret.make_interpreter(iter.property_grammar, target_module=iter.benchmark, cache_module=iter.benchmark)
    iter.property_interpreter = (p,x) -> (iter.properties_evaluated += 1; prop_interp(p,x))


    # ---------------------------
    #   2. Create properties
    # ---------------------------

    for (type, distance) in iter.normalized_distance_functions
        potential_properties = BFSIterator(iter.property_grammar, type, 
            max_depth = iter.max_property_depth, 
            max_size = iter.max_property_size,
        )

        # Keep only properties that don't produce an exception and cache the target values
        for p in potential_properties
            values = [iter.property_interpreter(p, (io.in[:_arg_out] = io.out; io.in)) for io in iter.problem.spec]

            if allequal(values) && !any(isnothing, values) && values[1] != -1
                dist = xs -> sum(isnothing(x) ? 1 : distance(target, x) for (target, x) in zip(values, xs))
                push!(iter.candidate_properties, Property(freeze_state(p), dist))
            end
        end
    end

    sort!(iter.candidate_properties, by = p -> depth(p.program))


    # ---------------------------
    #   3. Create extensions
    # ---------------------------

    # Copy the grammar to clear constraints as we will use another iterator to obtain extensions
    original_grammar = iter.solver.grammar
    grammar = deepcopy(original_grammar)
    clearconstraints!(grammar)

    # Iterate over all grammar types
    for type in unique(grammar.types)

        # Itertate over all extensions of that type up to the specified depth and size
        extensions = BFSIterator(grammar, type, 
            max_depth=iter.max_extension_depth,
            max_size=iter.max_extension_size)

        for extension in extensions
            extension = freeze_state(extension)

            # If an interpreter is defined, set the _val of the rulenode
            extension._val = [iter.interpreter(extension, io.in) for io in iter.problem.spec]

            # If this extension produces an error or an already existing output, skip it
            if any(isnothing, extension._val) || any(e._val == extension._val for e in iter.extensions[type])
                continue
            end

            # If it has the correct output type and is feasible with the original grammar constraints, add it to the first beam
            if type == iter.solver.grammar.rules[1] && all([check_tree(constraint, extension) for constraint in grammar.constraints])
                add_to_pool!(iter, extension)
            end

            # Always add it to the set of extensions
            push!(iter.extensions[type], extension)
        end
    end

    return nothing
end

function neighborhood(iter::PhalconGeneralizedProperties, program::AbstractRuleNode)
    grammar = iter.solver.grammar
    types = grammar.types

    function extend(program::AbstractRuleNode)
        program_type = types[get_rule(program)]
        combinations = Set()

        for rule_id in 1:length(grammar.rules)
            if types[rule_id] != program_type
                continue
            end

            for program_index in findall(t -> t == program_type, grammar.childtypes[rule_id])
            # for program_index in [0; findall(t -> t == program_type, grammar.childtypes[rule_id])]
                child_options = []

                for (index, child_type) in enumerate(grammar.childtypes[rule_id])
                    if index == program_index
                        push!(child_options, [program])
                    else
                        push!(child_options, iter.extensions[child_type])
                    end
                end

                for child_tuple in Iterators.product(child_options...)
                    children = collect(child_tuple)
                    new_program = RuleNode(rule_id, children)

                    push!(combinations, new_program)
                end
            end
        end

        return combinations
    end

    function extend_all_nodes(program::AbstractRuleNode)
        results = extend(program)

        for (child_index, child) in enumerate(program.children)
            new_child_options = extend_all_nodes(child)

            for new_child in new_child_options
                new_children = [i == child_index ? new_child : c for (i, c) in enumerate(program.children)]
                new_program = RuleNode(get_rule(program), new_children)
                push!(results, new_program)
            end
        end

        return results
    end

    return extend_all_nodes(program)
end

"""
    combine!(iter::AbstractBeamIterator)

Creates new programs by expanding all programs in the beam with all possible extensions.
Only selects the N best programs of these to create the new beam.
"""
function combine!(iter::PhalconGeneralizedProperties)
    neighbor_to_parent = Dict()

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

    sorted = sort(collect(neighbor_to_parent), by = x -> length(first(x)))

    for (neighbor, parent) in sorted
        add_to_pool!(iter, neighbor, parent)

        if length(iter.pool) == iter.pool_size && iter.pool[end].cost == 0
            break
        end

        if iter.pool[begin].cost == -1
            return [iter.pool[begin].program]
        end
    end

    # Only return programs that have not been expanded yet, otherwise they are already iterated over
    return [pool_entry.program for pool_entry in iter.pool if !pool_entry.has_been_expanded]
end

function refine_heuristic!(iter::PhalconGeneralizedProperties)
    interp = iter.property_interpreter

    optimal_heuristic_increase = count(output != io.out for pool_entry in iter.pool for (output, io) in zip(pool_entry.program._val, iter.problem.spec) if !any(isnothing, pool_entry.program._val))

    best_property = nothing
    best_increase = -1

    for property in iter.candidate_properties
        if property in iter.selected_properties
            continue
        end

        increase = 0
        for pool_entry in iter.pool
            values = [interp(property.program, (io.in[:_arg_out] = output; io.in)) for (output, io) in zip(pool_entry.program._val, iter.problem.spec)]
            increase += property.distance(values)
        end

        if increase > best_increase
            best_property = property
            best_increase = increase
        end

        if increase >= iter.increase_percentage_threshold * optimal_heuristic_increase
            break
        end
    end

    targets = [iter.property_interpreter(best_property.program, (io.in[:_arg_out] = io.out; io.in)) for io in iter.problem.spec]
    push!(iter.selected_properties, best_property)
    println("\nAdded property ($best_increase / $optimal_heuristic_increase)")
    @show targets
    prop = rulenode2expr(best_property.program, iter.property_grammar)
    @show prop

    return nothing
end


"""
    Base.iterate(iter::AbstractBeamIterator)

The initial call to the iterator. Initializes the beams and iterator's state.
"""
function Base.iterate(iter::PhalconGeneralizedProperties)
    initialize!(iter)

    return Base.iterate(
        iter,
        [pool_entry.program for pool_entry in iter.pool]
    )
end

"""
    Base.iterate(iter::AbstractBeamIterator)

Iterative call to the iterator. Perform the following:
1. If all programs from the current queue have been returned, expand the current beam and set the queue as the new beam (pruning already returned programs).
2. If after expansion the beam is empty, the iterator is exhausted.
3. Otherwise, return the next program from the queue.
"""
function Base.iterate(iter::PhalconGeneralizedProperties, state::Vector{<:AbstractRuleNode})
    # If the current queue is drained, new programs must be created
    if isempty(state)
        # If so, expand the current pool and set that result as the queue
        state = combine!(iter)
    end

    if isempty(state)
        if length(iter.selected_properties) >= iter.max_number_of_properties
            return nothing
        end

        refine_heuristic!(iter)
        empty!(iter.pool)
        
        for e in iter.extensions[iter.solver.grammar.rules[1]]
            add_to_pool!(iter, e)
        end

        state = [pool_entry.program for pool_entry in iter.pool]

        return Base.iterate(iter, state)
    end
    
    # Pop the first program from the queue and return
    return popfirst!(state), state
end