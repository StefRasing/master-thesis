"""
    abstract type AbstractGeneticIterator <: ProgramIterator end

Abstract type for GeneticIterator. This GeneticIterator works by sequentially creating new populations of programs
by combining programs from the current population and mutating them. Concretely, each generation the following happens:
    1. Create M (candidate_pool_size) candidate individuals, by:
        a. Selecting two random parents A and B from the current population
        b. Crossover:
            - Select a random subprogram from A of a type that exists in B
            - Select a random location from B of that type and replace it with that subprogram
        c. Mutate using one of the following operations:
            - Replace: replace a random subprogram with a random expression up to a certain size/depth of the same type
            - Insert: replace a random subprogram with a random grammar rule that uses that subprogram and fill the rest with random expression up to a certain size/depth
            - Delete: replace a random subprogram with any of its children
            (These mutation operations closely resemble how humans program; we can replace instructions, add lines, remove lines)
    2. Select the best N (population_size) according to a given cost function (cost)
    3. If the total cost of the population has been stable for a certain amount of generations (max_generations_without_improvement), terminate search

Grammar types introduce several difficulties regarding crossovers and mutations:
    - For crossover we need to check which types exists in a program
    - Also for crossover we need to efficiently select uniformly random subprograms of a certain type
    - As not every rule is suitable for insertion and deletation (e.g. String = int_to_string(Int)) we need to efficiently check which rules appear in a program
This necessitates a specialized RuleNode that also stores how many times each rule appears in itself.

"""
abstract type AbstractGeneticIterator <: ProgramIterator end


"""
    struct RuleNodeWithRuleCounts <: AbstractRuleNode

A RuleNode that also stores how many times each rule appears in itself. Contains the rule, children, rule_counts and caches outputs.
"""
struct RuleNodeWithRuleCounts <: AbstractRuleNode
    rule::Int
    children::Vector{RuleNodeWithRuleCounts}
    rule_counts::SparseVector{Int,Int}
    outputs::Vector{Any}
end

# Implement the AbstractRuleNode interface
HerbCore.isfilled(::RuleNodeWithRuleCounts)::Bool = true
HerbCore.isuniform(::RuleNodeWithRuleCounts)::Bool = true
HerbCore.get_rule(program::RuleNodeWithRuleCounts)::Int = program.rule
HerbCore.get_children(program::RuleNodeWithRuleCounts)::Vector{AbstractRuleNode} = program.children
Base.length(program::RuleNodeWithRuleCounts) = sum(program.rule_counts)

"""
    function RuleNodeWithRuleCounts(iter::ProgramIterator, rule::Int, children::Vector{RuleNodeWithRuleCounts})

Constructs a new RuleNodeWithRuleCounts given an ProgramIterator, rule id and list of children. Automatically computes
the new rule counts.
"""
function RuleNodeWithRuleCounts(iter::ProgramIterator, rule::Int, children::Vector{RuleNodeWithRuleCounts})
    # Creates a new rule count vector and add a count of one to the rule of this program
    rule_counts = SparseVector{Int, Int}(length(iter.solver.grammar.rules), Int[], Int[])
    rule_counts[rule] += 1
    
    # Add the rule counts of all children
    for c in children
        rule_counts += c.rule_counts
    end

    children_outputs = [child.outputs for child in children]
    return RuleNodeWithRuleCounts(rule, children, rule_counts, interp(iter, rule, children_outputs))
end

"""
    RuleNodeWithRuleCounts(iter::ProgramIterator, program::RuleNode)

Given an ProgramIterator, converts a RuleNode into a RuleNodeWithRuleCounts.
"""
RuleNodeWithRuleCounts(iter::ProgramIterator, program::RuleNode) = RuleNodeWithRuleCounts(iter, program.ind, RuleNodeWithRuleCounts[RuleNodeWithRuleCounts(iter, c) for c in program.children])


function RuleNodeWithRuleCounts(iter::ProgramIterator, program::CachedRuleNode)    
    rule = program.rule

    # Creates a new rule count vector and add a count of one to the rule of this program
    rule_counts = SparseVector{Int, Int}(length(iter.solver.grammar.rules), Int[], Int[])
    rule_counts[rule] += 1

    children = [RuleNodeWithRuleCounts(iter, c) for c in program.children]
    
    # Add the rule counts of all children
    for c in children
        rule_counts += c.rule_counts
    end

    return RuleNodeWithRuleCounts(rule, children, rule_counts, program.outputs)
end

"""
    HerbCore.RuleNode(program::RuleNodeWithRuleCounts)

Converts a RuleNodeWithRuleCounts into a RuleNode.
"""
HerbCore.RuleNode(program::RuleNodeWithRuleCounts) = HerbCore.RuleNode(program.rule, [HerbCore.RuleNode(c) for c in program.children])

"""
    function random_subtree(iter::ProgramIterator, program::RuleNodeWithRuleCounts, allowed_rules::Vector{Bool})::Tuple{RuleNodeWithRuleCounts,Vector{Int64}}

Given an ProgramIterator, RuleNodeWithRuleCounts and vector of allowed grammar rules, randomly selects a subprogram
of one of the allowed rules. The RuleNodeWithRuleCounts structure allows to do so very efficiently. This method only
needs to traverse the RuleNodeWithRuleCounts up to the randomly selected subprogram.

Returns a tuple with the random subprogram as RuleNodeWithRuleCounts and a Vector{Int64} containing the path to that subprogram.
"""
function random_subtree(iter::ProgramIterator, program::RuleNodeWithRuleCounts, allowed_rules::Vector{Bool})::Tuple{RuleNodeWithRuleCounts,Vector{Int64}}
    cs = program.children

    # This function either selects this program as subprogram or recurse on any child
    # To uniformly select subprogram, we compute weights as the total amount of allowed rules in each child

    # The current program gets a weight of 1 if its rule is allowed, 0 otherwise
    program_weight = allowed_rules[program.rule]

    # Each child is weighted by the sum of allowed rules appear in that child
    child_weights = [sum(c.rule_counts[allowed_rules]) for c in cs]

    # Sample an index according to the weights. Index 0 indicates that the current program is selected
    index = sample(0:length(cs), Weights([program_weight; child_weights]))

    # If the index was 0, return the current program and an empty path
    index == 0 && return program, Int64[]

    # Otherwise recurse and return that result and extend the path
    node, path = random_subtree(iter, cs[index], allowed_rules)
    return node, [index; path]
end

"""
    function replace_at_path(iter::ProgramIterator, program::RuleNodeWithRuleCounts, path::Vector{Int}, replacement::RuleNodeWithRuleCounts)::RuleNodeWithRuleCounts

Given an ProgramIterator and as Vector{Int}, replaces the subprogram from program at that path with a replacement.
Returns a the resulting RuleNodeWithRuleCounts.
"""
function replace_at_path(iter::ProgramIterator, program::RuleNodeWithRuleCounts, path::Vector{Int}, replacement::RuleNodeWithRuleCounts)::RuleNodeWithRuleCounts
    # If the path is empty, simply return the replacement
    isempty(path) && return replacement

    # Otherwise, pop the first index from the path
    index = popfirst!(path)

    # Copy all children, except for the one at the popped index; recurse on that
    children = [i == index ? replace_at_path(iter, c, path, replacement) : c for (i, c) in enumerate(program.children)]
    
    # Construct a new RuleNodeWithRuleCounts which automatically updates rule counts
    return RuleNodeWithRuleCounts(iter, program.rule, children)
end

"""
    struct Individual

Store an Individual living in a population. Contains the program and the cost.
"""
struct Individual
    program::RuleNodeWithRuleCounts
    cost::Number
    parents::Union{Nothing, Individual, Tuple{Individual, Individual}}
    crossover::Union{Nothing,RuleNodeWithRuleCounts}
    crossover_parts::Union{Nothing,Tuple{RuleNodeWithRuleCounts, RuleNodeWithRuleCounts}}
    mutation::Union{Nothing,Symbol}
end

function pretty_print(ind::Individual, grammar::AbstractGrammar)
    println(rulenode2expr(ind.program, grammar))
    _pretty_print(ind, "", grammar)
end


function _pretty_print(ind::Individual, prefix::String, grammar::AbstractGrammar)
    ind.parents === nothing && return

    if ind.parents isa Tuple
        p1, p2 = ind.parents
        replacement, removed = ind.crossover_parts

        # Meta
        println(prefix * "├── Parent 1:        ", rulenode2expr(p1.program, grammar))
        println(prefix * "│   └── replacement: ", rulenode2expr(replacement, grammar))
        println(prefix * "├── Parent 2:        ", rulenode2expr(p2.program, grammar))
        println(prefix * "│   └── removed:     ", rulenode2expr(removed, grammar))

        if ind.mutation != :none
            println(prefix * "├── Crossover:       ", rulenode2expr(ind.crossover, grammar))
            println(prefix * "│   ├── mutation:    ", ind.mutation)
            println(prefix * "│   └── result:      ", rulenode2expr(ind.program, grammar))
        end

        # parent 1
        if !isnothing(p1.parents)
            println(prefix * "├── Parent 1 origin:")
            _pretty_print(p1, prefix * "│   ", grammar)
        else
            println(prefix * "├── Parent 1 origin: extensions")
        end

        # parent 2
        if !isnothing(p2.parents)
            println(prefix * "└── Parent 2 origin: ")
            _pretty_print(p2, prefix * "    ", grammar)
        else
            println(prefix * "└── Parent 2 origin: extensions")
        end
    else
        p = ind.parents

        println(prefix * "├── Parent:       ", rulenode2expr(p.program, grammar))
        println(prefix * "│   ├── mutation: ", ind.mutation)
        println(prefix * "│   └── result:   ", rulenode2expr(ind.program, grammar))

        # parent
        if !isnothing(p.parents)
            println(prefix * "└── Parent origin:")
            _pretty_print(p, prefix * "    ", grammar)
        else
            println(prefix * "└── Parent origin:   extension")
        end
    end
end

"""
    function Base.isless(a::Individual, b::Individual)

An Individual is less than another if it has a lower costs, breaking ties by chosing the smallest program.
"""
function Base.isless(a::Individual, b::Individual)
    a.cost != b.cost && return a.cost < b.cost
    return length(a.program) < length(b.program)
end

function Base.:(==)(a::Individual, b::Individual)
    a.cost == b.cost &&
    length(a.program) == length(b.program) &&
    a.program == b.program
end

@programiterator mutable GeneticIterator(
    # Problem specification
    benchmark = nothing,
    problem = nothing,

    # Hyperparemeters
    cost::Function = nothing,
    population_size::Int = 10,
    candidate_pool_size::Int = 1000,
    max_generations_without_improvement::Int = 5,
    max_extension_size::Int = 1,
    max_initial_population_size::Int = 2,
    rule_costs::Vector{Int} = [],
    prune_node_by_output::Union{Nothing,Function} = nothing,

    # Internal structures
    population::Vector{Individual} = Individual[],
    extensions::DefaultDict{Symbol,Vector{RuleNodeWithRuleCounts}} = DefaultDict{Symbol,Vector{RuleNodeWithRuleCounts}}(() -> RuleNodeWithRuleCounts[]),

    # Caching
    recursive_rules::Vector{Bool} = Bool[],
    rules_in_recursive_rules::Vector{Bool} = Bool[],

    # Interpreter
    interpreter = nothing,
    programs_evaluated::Int = 0,
) <: AbstractGeneticIterator


"""
    Individual(iter::ProgramIterator, program::RuleNodeWithRuleCounts)

Given a GeneticIterator and RuleNodeWithRuleCounts, create a new Individual. Automatically calls the cost function.
"""
Individual(iter::GeneticIterator, program::RuleNodeWithRuleCounts) = Individual(program, outputs_to_cost(iter, program.outputs), nothing, nothing, nothing, nothing)

Individual(iter::GeneticIterator, program::RuleNodeWithRuleCounts, parents::Tuple{Individual, Individual}, crossover::RuleNodeWithRuleCounts, crossover_parts::Tuple{RuleNodeWithRuleCounts, RuleNodeWithRuleCounts}, mutation::Symbol) = Individual(program, outputs_to_cost(iter, program.outputs), parents, crossover, crossover_parts, mutation)

Individual(iter::GeneticIterator, program::RuleNodeWithRuleCounts, parent::Individual, mutation::Symbol) = Individual(program, outputs_to_cost(iter, program.outputs), parent, nothing, nothing, mutation)


"""
    function update_cost_function(iter::GeneticIterator, cost::Function)::Nothing

Function needed by the Phalcon interface. Changes the cost function and reset population.
"""
function update_cost_function(iter::GeneticIterator, cost::Function)::Nothing
    # Update cost
    iter.cost = cost

    old_programs = [ind.program for ind in iter.population]

    empty!(iter.population)
    for program in old_programs
        add_to_population!(iter, Individual(iter, program))
    end

    return nothing
end

"""
    function find_solution(iter::GeneticIterator)::Union{RuleNode,Nothing}

Function needed by the Phalcon interface. Attempts to find a solution. Terminates if the total cost of the
population hasn't improvded for N generation (max_generations_without_improvement).

Returns a solution as RuleNode, or nothing if search failed.
"""
function find_solution(iter::GeneticIterator)::Union{RuleNode,Nothing}
    # Count number of stable populations and store the last seen cost
    stable_populations = 0
    population_cost = sum(individual.cost for individual in iter.population)
    iterations = 0

    # Loop until stability critereon has been met
    while stable_populations < iter.max_generations_without_improvement
        combine!(iter)
        iterations += 1

        # Cost if -Inf means a solution has been found. In that case convert program to RuleNode and return.
        if iter.population[begin].cost == -Inf
            return RuleNode(iter.population[begin].program)
        end

        # If the new_population_cost is the same as before, increment stable_populations, otherwise reset it
        new_population_cost = sum(individual.cost for individual in iter.population)
        stable_populations = new_population_cost == population_cost ? stable_populations + 1 : 0
        population_cost = new_population_cost

        new_population_cost == 0 && return nothing
    end

    # Search failed, return nothing.
    return nothing
end

"""
    local_optimum_outputs(iter::GeneticIterator)::Vector{Vector{Any}}

Function needed by the Phalcon interface. Returns the outputs of the current local optimum, which is the
population in the case of genetic search.
"""
local_optimum_outputs(iter::GeneticIterator)::Vector{Vector{Any}} = [individual.program.outputs for individual in iter.population]

"""
    function outputs_to_cost(iter::GeneticIterator, outputs::Vector)

Given an GeneticIterator, maps a Vector of outputs to their cost. Basically is wrapper for the cost function that
ensures that programs that produce exceptions (return nothing) have Inf cost and programs that produce the target
outputs have a cost of -Inf.
"""
function outputs_to_cost(iter::GeneticIterator, outputs::Vector)
    # If any output is nothing, return +Inf
    any(isnothing, outputs) && return Inf

    # Obtain target outputs
    targets = [io.out for io in iter.problem.spec]

    # If problem is solved, return -Inf
    outputs == targets && return -Inf

    # Otherwise, call the provided cost function
    return iter.cost(zip(outputs, targets))
end

"""
    function initialize!(iter::GeneticIterator)::Nothing

Initializes the GeneticIterator. This function performs the following:
    - Precompute which rules are suitable for deletion/insertion. These rules are called recursive rules as
      their output type must also appear as one of the input types. E.g. `String x String -> String` is recursive
      but S`tring -> Int` is not.
    - Builds the interpreter and ensures that programs_evaluated is computed correctly.
    - Creates the set of possible extensions that can be used by the genetic operators.
    - Fills the intial population with the N best extensions.

"""
function initialize!(iter::GeneticIterator)::Nothing
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

    # Build interpreter
    iter.interpreter = HerbInterpret.make_output_interpreter(grammar, target_module=iter.benchmark, cache_module=iter.benchmark)
    types = Vector{Symbol}(unique(grammar.types))


    # Create extensions that produce unique outputs
    extensions = LazyCostBasedBus(
        grammar,
        types,
        iter.max_extension_size,
        iter.rule_costs,
        (r, o) -> interp(iter, r, o),
        isnothing,
    )
    
    # Iterate over all extensions and add to initial population if its of the correct starting symbol
    for extension in extensions
        type = grammar.types[get_rule(extension)]
        extension = RuleNodeWithRuleCounts(iter, extension)
        push!(iter.extensions[type], extension)

        if type == get_starting_symbol(iter)
            add_to_population!(iter, Individual(iter, extension))
        end
    end

    # Iterate over the extra programs of the initial population
    for size in (iter.max_extension_size+1):iter.max_initial_population_size
        for extension in get_programs(extensions, :Start, size)
            type = grammar.types[get_rule(extension)]
            extension = RuleNodeWithRuleCounts(iter, extension)
            push!(iter.extensions[type], extension)
            add_to_population!(iter, Individual(iter, extension))
        end
    end

    # If some type doesn't have any extensions, that type can never be reached and thats to be prevented
    for type in unique(grammar.types)
        isempty(iter.extensions[type]) && throw(ArgumentError("Extension depth to low for any extension of type $type"))
    end

    return nothing
end

Base.length(x) = 1

function interp(iter::GeneticIterator, rule_id::Int, children_outputs::Vector{Vector{Any}})
    # Interp rule on outputs
    res = iter.interpreter(rule_id, children_outputs, iter.problem.spec)

    # If program should be pruned by its output, return nothings
    !isnothing(iter.prune_node_by_output) && any(iter.prune_node_by_output(io, y) for (io, y) in zip(iter.problem.spec, res)) && return fill(nothing, length(iter.problem.spec))
    
    res
end

"""
    function add_to_population!(iter::GeneticIterator, program::RuleNodeWithRuleCounts)::Nothing

Given a GeneticIterator, adds a RuleNodeWithRuleCounts to the population. This function ensures that
the population only keeps the N best programs with unique outputs.
"""
function add_to_population!(iter::GeneticIterator, new_individual::Individual)::Nothing
    iter.programs_evaluated += 1
    
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
                    iter.population[i] = new_individual
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

"""
    function crossover(iter::GeneticIterator, parent_1::RuleNodeWithRuleCounts, parent_2::RuleNodeWithRuleCounts)::RuleNodeWithRuleCounts

Given a GeneticIterator and two parent RuleNodeWithRuleCounts, performs a crossover. A crossover is done by selecting a random
subtree from the parent_1 and replacing a random subtree from parent_2 with that subtree. For correct typing, the type of the
replacement substree must also exists in parent_2.

Returns the resulting RuleNodeWithRuleCounts.
"""
function crossover(iter::GeneticIterator, program_1::RuleNodeWithRuleCounts, program_2::RuleNodeWithRuleCounts)::Tuple{RuleNodeWithRuleCounts, Tuple{RuleNodeWithRuleCounts, RuleNodeWithRuleCounts}}
    types = iter.solver.grammar.types

    # We may only select subprograms of types that are present in parent_2
    allowed_types = unique([types[rule] for (rule, rule_count) in enumerate(program_2.rule_counts) if rule_count > 0])
    allowed_rules = [type in allowed_types for type in types]

    # Select a random subprogram from program_1 of these types
    replacement, _ = random_subtree(iter, program_1, allowed_rules)
    replacement_type = types[replacement.rule]
    replacement_rules = [type == replacement_type for type in types]

    # Find a random path of program_2 of the selected type
    removed, replacement_path = random_subtree(iter, program_2, replacement_rules)

    # Replace and return
    return replace_at_path(iter, program_2, replacement_path, replacement), (replacement, removed)
end

"""
    function mutate(iter::GeneticIterator, individual::RuleNodeWithRuleCounts)::RuleNodeWithRuleCounts

Given a GeneticIterator and RuleNodeWithRuleCounts, performs one of the three mutation operations:
    - Replace: replace a random subprogram with a random expression up to a certain size/depth of the same type
    - Insert: replace a random subprogram with a random grammar rule that uses that subprogram and fill the rest with random expression up to a certain size/depth
    - Delete: replace a random subprogram with any of its children
These mutation operations closely resemble how humans program; we can replace instructions, add lines, remove lines.

Returns the resulting RuleNodeWithRuleCounts.
"""
function mutate(iter::GeneticIterator, individual::RuleNodeWithRuleCounts)::Tuple{RuleNodeWithRuleCounts, Symbol}
    grammar = iter.solver.grammar
    types = grammar.types

    # Select a random mutation operation
    operations = [:replace]

    # Check if we can perform a delete operation (only if a recursive rule exists in the program)
    if any(count -> count > 0, individual.rule_counts[iter.recursive_rules])
        push!(operations, :delete)
    end

    # Check if we can perform am insert operation (only if a rule appearing in recurisve rules exists)
    if any(count -> count > 0, individual.rule_counts[iter.rules_in_recursive_rules])
        push!(operations, :insert)
    end

    operation = rand(operations)

    if operation == :replace
        # Select a random subprogram to replace. Every node is allowed in this case
        old_node, replacement_path = random_subtree(iter, individual, [true for _ in types])

        # Obtain type and select a random rule of that type and fill with random extensions
        replacement_type = types[old_node.rule]
        replacement_rule = rand([rule_id for (rule_id, type) in enumerate(grammar.types) if type == replacement_type])
        children = [rand(iter.extensions[child_type]) for child_type in grammar.childtypes[replacement_rule]]
        replacement = RuleNodeWithRuleCounts(iter, replacement_rule, children)
        replacement = rand(iter.extensions[replacement_type])

        # Replace and return
        return replace_at_path(iter, individual, replacement_path, replacement), :replace

    elseif operation == :insert
        # Select a random node of a type that can be used in recurisve rules.
        node, replacement_path = random_subtree(iter, individual, iter.rules_in_recursive_rules)

        # Select a random recurisve rule of the correct type
        node_type = types[node.rule]
        rule_id = rand([rule_id for (rule_id, type) in enumerate(types) if iter.recursive_rules[rule_id] && type == node_type])

        # Select a random index where the old node will be placed
        node_index = rand([index for (index, type) in enumerate(grammar.childtypes[rule_id]) if type == node_type])

        # Fill the other places of the rule with random expressions from the extensions
        children = [index == node_index ? node : rand(iter.extensions[type]) for (index, type) in enumerate(grammar.childtypes[rule_id])]

        # Build the replacement
        replacement = RuleNodeWithRuleCounts(iter, rule_id, children)

        # Replace and return
        return replace_at_path(iter, individual, replacement_path, replacement), :insert

    elseif operation == :delete
        # Select a random subprogram that is suitable for deletion
        node, replacement_path = random_subtree(iter, individual, iter.recursive_rules)

        # Select any of its children that have the same type as its replacement
        type = types[node.rule]

        # Replace and return
        replacement = rand([c for c in node.children if types[c.rule] == type])
        return replace_at_path(iter, individual, replacement_path, replacement), :delete
    end
end

"""
    function combine!(iter::GeneticIterator)::Nothing

Creates a new generation by creating M (candidate_pool_size) new individuals and selecting the N best ones:
    - Select two random parents 1 and 2
    - Create four individuals:
        1. Mutate parent 1
        2. Mutate parent 2
        3. Crossover parent 1 and 2
        4. Mutate individual 3
"""
function combine!(iter::GeneticIterator)::Nothing
    # It does not make sense to select parents with size 1 as that will always create an already existing extension
    selection_pool = [ind for ind in iter.population if length(ind.program) > 1]
    
    # Create candidates
    for _ in 1:4:iter.candidate_pool_size
        # Select parents using tournament selection
        parent_1 = rand(selection_pool)
        parent_2 = rand(selection_pool)
        program_1 = parent_1.program
        program_2 = parent_2.program

        # Crossover and mutate
        child_1, mutation_1 = mutate(iter, program_1)
        child_2, mutation_2 = mutate(iter, program_2)
        child_3, crossover_parts = crossover(iter, program_1, program_2)
        child_4, mutation_4 = mutate(iter, child_3)

        # Create individuals
        individual_1 = Individual(iter, child_1, parent_1, mutation_1)
        individual_2 = Individual(iter, child_2, parent_2, mutation_2)
        individual_3 = Individual(iter, child_3, (parent_1, parent_2), child_3, crossover_parts, :none)
        individual_4 = Individual(iter, child_4, (parent_1, parent_2), child_3, crossover_parts, mutation_4)
        
        # Add both to population
        add_to_population!(iter, individual_1)
        add_to_population!(iter, individual_2)
        add_to_population!(iter, individual_3)
        add_to_population!(iter, individual_4)

        iter.population[begin].cost == -Inf && return nothing
        length(iter.population) == iter.population_size && iter.population[end].cost == 0 && return nothing
    end

    return nothing
end


"""
    mutable struct GeneticIteratorState

Contains the current queue of Individual's and a list of past_population_costs to check for the termination critereon.
"""
mutable struct GeneticIteratorState
    queue::Vector{Individual}
    past_population_costs::Vector{Number}
end

"""
    GeneticIteratorState()

Creates an empty GeneticIteratorState.
"""
GeneticIteratorState() = GeneticIteratorState(Individual[], Number[])

"""
    function add_new_population!(state::GeneticIteratorState, population::Vector{Individual})::Nothing

Alters a given GeneticIteratorState after a new population has been combined. Automatically updates queue
and the past_population_costs vector.
"""
function add_new_population!(state::GeneticIteratorState, population::Vector{Individual})::Nothing
    total_cost = sum(Number[individual.cost for individual in population])
    state.queue = copy(population)
    push!(state.past_population_costs, total_cost)
    return nothing
end


function Base.iterate(iter::GeneticIterator)
    initialize!(iter)

    # Initialize iterator state and start iterating
    state = GeneticIteratorState()
    add_new_population!(state, iter.population)

    return Base.iterate(iter, state)
end

function Base.iterate(iter::GeneticIterator, state::GeneticIteratorState)
    if isempty(state.queue)
        # If the last n generations had constant cost, terminate search
        n = iter.max_generations_without_improvement
        if length(state.past_population_costs) >= n && allequal(state.past_population_costs[end-n+1:end])
            return nothing
        end

        # Otherwise, create new population and add to state
        combine!(iter)
        add_new_population!(state, iter.population)
    end

    # Return program of first queue item and state
    return popfirst!(state.queue).program, state
end