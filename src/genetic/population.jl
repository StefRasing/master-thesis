"""
    Individual(iter::ProgramIterator, program::RuleNodeWithRuleCounts)

Given a GeneticIterator and RuleNodeWithRuleCounts, create a new Individual. Automatically calls the cost function.
"""
Individual(iter::GeneticIterator, program::RuleNodeWithRuleCounts) = Individual(program, outputs_to_cost(iter, program.outputs), nothing, nothing, nothing, nothing)

Individual(iter::GeneticIterator, program::RuleNodeWithRuleCounts, parents::Tuple{Individual, Individual}, crossover::RuleNodeWithRuleCounts, crossover_parts::Tuple{RuleNodeWithRuleCounts, RuleNodeWithRuleCounts}, mutation::Symbol) = iter.track_ancestry ? Individual(program, outputs_to_cost(iter, program.outputs), parents, crossover, crossover_parts, mutation) : Individual(iter, program)

Individual(iter::GeneticIterator, program::RuleNodeWithRuleCounts, parent::Individual, mutation::Symbol) = iter.track_ancestry ? Individual(program, outputs_to_cost(iter, program.outputs), parent, nothing, nothing, mutation) : Individual(iter, program)


"""
    function update_cost_function(iter::GeneticIterator, cost::Function; deadline::Real = Inf)::Nothing

Function needed by the Phalcon interface. Changes the cost function and reset population.
"""
function update_cost_function(iter::GeneticIterator, cost::Function; deadline::Real = Inf)::Nothing
    # Update cost
    iter.cost = cost

    empty!(iter.population)
    for program in iter.extensions[get_starting_symbol(iter)]
        _check_deadline(deadline)
        add_to_population!(iter, Individual(iter, program); count_program=false)
    end

    return nothing
end

"""
    function initialize!(iter::GeneticIterator; deadline::Real = Inf)::Nothing

Initializes the GeneticIterator. This function performs the following:
    - Precompute which rules are suitable for deletion/insertion. These rules are called recursive rules as
      their output type must also appear as one of the input types. E.g. `String x String -> String` is recursive
      but S`tring -> Int` is not.
    - Builds the interpreter and ensures that programs_evaluated is computed correctly.
    - Creates the set of possible extensions that can be used by the genetic operators.
    - Fills the intial population with the N best extensions.

"""
function initialize!(iter::GeneticIterator; deadline::Real = Inf)::Nothing
    _check_deadline(deadline)
    grammar = iter.solver.grammar
    types = grammar.types

    #=
    Cache rules that are suitable for deletion and insertion. A recurisve rule is a rule that has 
    its output type also as an input type. For example a rule String x String -> String is recurisve, 
    but String -> Int is not. Only recursive rules can be used for deletion.

    Insertion can only be performed on types that appear in recurisve rules.
    =#
    iter.recursive_rules = [type in grammar.childtypes[rule_id] for (rule_id, type) in enumerate(types)]
    recurisve_types = unique(types[iter.recursive_rules])
    iter.rules_in_recursive_rules = [type in recurisve_types for type in types]

    # A supplied interpreter belongs to this unchanged grammar/module context.
    # Experiment runners prepare it before timing; standalone callers construct
    # it here, inside initialization's budget.
    if isnothing(iter.interpreter)
        iter.interpreter = HerbInterpret.make_output_interpreter(grammar, target_module=iter.benchmark, cache_module=iter.benchmark)
    end
    types = Vector{Symbol}(unique(grammar.types))


    # Create extensions that produce unique outputs
    extensions = ResumableCostBasedBus(
        grammar,
        types,
        iter.max_extension_size,
        iter.rule_costs,
        (r, o) -> begin
            iter.programs_evaluated += 1
            interp(iter, r, o)
        end,
        isnothing;
        deadline=deadline,
    )
    
    # Iterate over all extensions and add to initial population if its of the correct starting symbol
    for extension in extensions
        _check_deadline(deadline)
        type = grammar.types[get_rule(extension)]
        extension = RuleNodeWithRuleCounts(iter, extension)
        push!(iter.extensions[type], extension)

        if type == get_starting_symbol(iter)
            add_to_population!(iter, Individual(iter, extension); count_program=false)
        end
    end

    # Iterate over the extra programs of the initial population
    for size in (iter.max_extension_size+1):iter.max_initial_population_size
        for extension in get_programs(extensions, :Start, size)
            _check_deadline(deadline)
            type = grammar.types[get_rule(extension)]
            extension = RuleNodeWithRuleCounts(iter, extension)
            push!(iter.extensions[type], extension)
            add_to_population!(iter, Individual(iter, extension); count_program=false)
        end
    end

    # If some type doesn't have any extensions, that type can never be reached and thats to be prevented
    for type in unique(grammar.types)
        isempty(iter.extensions[type]) && throw(ArgumentError("Extension depth to low for any extension of type $type"))
    end

    return nothing
end

"""
    function add_to_population!(iter::GeneticIterator, program::RuleNodeWithRuleCounts)::Nothing

Given a GeneticIterator, adds a RuleNodeWithRuleCounts to the population. This function ensures that
the population only keeps the N best programs with unique outputs.
Set count_program=false for already counted initialization candidates or cached rescoring.
"""
function add_to_population!(iter::GeneticIterator, new_individual::Individual; count_program::Bool=true)::Nothing
    count_program && (iter.programs_evaluated += 1)
    
    # If the cost is infinity, skip the program
    new_individual.cost == Inf && return nothing

    length(new_individual.program) > get_max_size(iter) && return nothing

    # If the population is full and the new individual has a higher cost than the worst in the population, we can terminate
    length(iter.population) >= iter.population_size && new_individual > iter.population[end] && return nothing
    
    #= Otherwise, add the program to the population
    
    The main difficulty is checking whether a equal (or equivalent program with observation_equivalance) exists in the population.
    For this, we only wish to check the programs (or outputs) for individual that have the same cost.
    
    For this we find the range of equal costs: 
     - The last index in the array that has a lower cost
     - The first index in the array that has a higher cost
    =#
    first_index = searchsortedfirst([e.cost for e in iter.population], new_individual.cost)
    last_index = searchsortedlast([e.cost for e in iter.population], new_individual.cost)

    # If last_index > first_index, there is no entry with the same cost, and this step can be skipped
    if first_index <= last_index
        
        # To avoid duplicates, we check every individual in this range and see if the program or outputs are already present
        for i in first_index:last_index

            # Check if the programs are equal; abort if so
            iter.population[i].program == new_individual.program && return nothing

            # Ccheck if the outputs are equal; keep the shortest program in that case
            if iter.population[i].program.outputs == new_individual.program.outputs
                if new_individual < iter.population[i]
                    deleteat!(iter.population, i)
                    insert!(iter.population, searchsortedlast(iter.population, new_individual) + 1, new_individual)
                end

                return nothing
            end
        end
    end

    index = searchsortedlast(iter.population, new_individual)

    # If the entry made it through all the checks above, insert it
    insert!(iter.population, index + 1, new_individual)

    # If that exceeded the population size, pop the worst individual (located at the end)
    if length(iter.population) > iter.population_size
        pop!(iter.population)
    end

    return nothing
end

