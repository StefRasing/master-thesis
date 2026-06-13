abstract type AbstractGeneticPhalcon <: ProgramIterator end


@programiterator mutable GeneticPhalcon(
    problem = nothing,
    
    population_size::Int = 0,
    max_extension_depth::Int = 1,
    max_extension_size::Int = 1,
    offspring_per_parent::Int = 100,

    increase_band::Tuple{Float64,Float64} = (0.7, 0.9),
    grammar_to_property_grammar::Function = identity,
    max_property_depth::Int = 4,
    max_property_size::Int = 6,
    max_number_of_properties::Int = typemax(Int),
    
    pool::Vector{PoolEntry} = PoolEntry[],
    extensions::DefaultDict{Symbol,Vector{AbstractRuleNode}} = DefaultDict{Symbol,Vector{AbstractRuleNode}}(() -> AbstractRuleNode[]),
    candidate_properties::Vector{Tuple{AbstractRuleNode, Any}} = Tuple{AbstractRuleNode, Any}[],
    selected_properties::Vector{Tuple{AbstractRuleNode, Any}} = Tuple{AbstractRuleNode, Any}[],

    benchmark = nothing,
    property_grammar = nothing,
    interpreter = nothing,
    property_interpreter = nothing,

    programs_evaluated::Int = 0,
    properties_evaluated::Int = 0,

    extensions_to_distances = DefaultDict(() -> []),
) <: AbstractGeneticPhalcon

function heuristic_cost(iter::GeneticPhalcon, program::AbstractRuleNode)::Number
    spec = iter.problem.spec

    if isnothing(program._val) || length(program._val) == 0
        program._val = [iter.interpreter(program, io.in) for io in spec]
    end

    outputs = program._val

    if any(isnothing, outputs) || any(e -> length(first(e)) > 2*length(last(e).out), zip(outputs, spec))
        return typemax(Int)
    end

    if all(output == io.out for (output, io) in zip(outputs, spec))
        return -1
    end

    return count(
        iter.property_interpreter(property, (io.in[:_arg_out] = output; io.in)) != target_value
        for (property, target_values) in iter.selected_properties
        for (output, io, target_value) in zip(outputs, spec, target_values)
    )
end

"""
    Base.add_to_pool!(iter::AbstractBeamIterator, beam_entry::BeamEntry)

Adds a program to the pool, ensuring that the pool size is not exceeded and only the best programs are kept.
"""
function add_to_pool!(iter::GeneticPhalcon, program::AbstractRuleNode, parent=nothing)    
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
    if length(iter.pool) >= iter.population_size && pool_entry >= iter.pool[end]
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
    if length(iter.pool) > iter.population_size
        pop!(iter.pool)
    end

    return nothing
end

"""
    initialize!(iter::AbstractBeamIterator)

Initializes the iterator by creating all extensions and setting the first beam.
"""
function initialize!(iter::GeneticPhalcon)
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

    potential_properties = BFSIterator(iter.property_grammar, :Start, 
        max_depth = iter.max_property_depth, 
        max_size = iter.max_property_size,
    )

    # Keep only properties that don't produce an exception and cache the target values
    for p in potential_properties
        values = [iter.property_interpreter(p, (io.in[:_arg_out] = io.out; io.in)) for io in iter.problem.spec]

        if !any(isnothing, values)
            push!(iter.candidate_properties, (freeze_state(p), values))
        end
    end


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

function offspring(iter::GeneticPhalcon, program::AbstractRuleNode)
    grammar = iter.solver.grammar
    types = grammar.types

    function mutate_at_path(program::AbstractRuleNode, path::Vector{Int})
        if length(path) == 0
            type = types[get_rule(program)]
            rule_id = rand(findall(x -> x == type, types))
            program_index = rand([0; findall(t -> t == type, grammar.childtypes[rule_id])])
            children = AbstractRuleNode[]

            for (index, child_type) in enumerate(grammar.childtypes[rule_id])
                if index == program_index
                    push!(children, program)
                else
                    push!(children, rand(iter.extensions[child_type]))
                end
            end

            return RuleNode(rule_id, children)
        end

        children = [i == path[begin] ? mutate_at_path(c, path[begin+1:end]) : c for (i,c) in enumerate(get_children(program))]

        return RuleNode(get_rule(program), children)
    end

    function all_paths(program::AbstractRuleNode)
        res = [Int[]]

        for (i,c) in enumerate(get_children(program))
            child_paths = all_paths(c)

            for child_path in child_paths
                push!(res, [i; child_path])
            end
        end

        return res
    end

    paths = all_paths(program)

    return [mutate_at_path(program, rand(paths)) for _ in 1:iter.offspring_per_parent]
end

"""
    combine!(iter::AbstractBeamIterator)

Creates new programs by expanding all programs in the beam with all possible extensions.
Only selects the N best programs of these to create the new beam.
"""
function combine!(iter::GeneticPhalcon)
    for (i, pool_entry) in enumerate(collect(iter.pool))
        if pool_entry.has_been_expanded
            continue
        end

        pool_entry.has_been_expanded = true

        for child in offspring(iter, pool_entry.program)
            add_to_pool!(iter, child, (pool_entry, i))

            # if length(iter.pool) == iter.population_size && iter.pool[end].cost <= best_cost
            #     break
            # end

            if iter.pool[end].cost == 0
                ret = [pool_entry.program for pool_entry in iter.pool if !pool_entry.has_been_expanded]

                for e in iter.pool
                    e.has_been_expanded = true
                end

                return ret
            end

            if iter.pool[begin].cost == -1
                return [iter.pool[begin].program]
            end
        end
    end

    # Only return programs that have not been expanded yet, otherwise they are already iterated over
    return [pool_entry.program for pool_entry in iter.pool if !pool_entry.has_been_expanded]
end

function refine_heuristic!(iter::GeneticPhalcon)
    interp = iter.property_interpreter

    optimal_heuristic_increase = count(output != io.out for pool_entry in iter.pool for (output, io) in zip(pool_entry.program._val, iter.problem.spec) if !any(isnothing, pool_entry.program._val))

    best_property = nothing
    best_increase = -1
    best_target_values = nothing

    for (property, target_values) in iter.candidate_properties
        increase = 0
        satisfyiable = false

        for pool_entry in iter.pool
            values = [interp(property, (io.in[:_arg_out] = output; io.in)) for (output, io) in zip(pool_entry.program._val, iter.problem.spec)]
            increase += sum(values .!= target_values)
            satisfyiable = satisfyiable || values == target_values
        end

        if !satisfyiable
            continue
        end

        if increase > best_increase
            best_property = property
            best_increase = increase
            best_target_values = target_values
        end

        if increase >= first(iter.increase_band) * optimal_heuristic_increase
            break
        end
    end

    push!(iter.selected_properties, (best_property, best_target_values))
    println("\nAdded property ($best_increase / $optimal_heuristic_increase): $best_target_values")
    prop = rulenode2expr(best_property, iter.property_grammar)
    @show prop

    return nothing
end


"""
    Base.iterate(iter::AbstractBeamIterator)

The initial call to the iterator. Initializes the beams and iterator's state.
"""
function Base.iterate(iter::GeneticPhalcon)
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
function Base.iterate(iter::GeneticPhalcon, state::Vector{<:AbstractRuleNode})
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