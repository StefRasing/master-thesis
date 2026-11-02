"""
    struct RuleNodeWithRuleCounts <: AbstractRuleNode

A RuleNode that also stores how many times each rule appears in itself. Contains the rule, children, rule_counts and caches outputs.
"""
struct RuleNodeWithRuleCounts <: AbstractRuleNode
    rule::Int
    children::Vector{RuleNodeWithRuleCounts}
    rule_counts::SparseVector{Int,Int}
    outputs::Vector # Preserve each program's concrete output element type.
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
    index = sample(iter.rng, 0:length(cs), Weights([program_weight; child_weights]))

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

