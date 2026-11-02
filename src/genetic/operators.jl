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

    operation = rand(iter.rng, operations)

    if operation == :replace
        # Select a random subprogram to replace. Every node is allowed in this case
        old_node, replacement_path = random_subtree(iter, individual, [true for _ in types])

        # Obtain type and select a random rule of that type and fill with random extensions
        replacement_type = types[old_node.rule]
        # Keep the discarded construction for now: removing it changes RNG consumption
        # and interpreter calls. See docs/genetic-search.md before optimizing.
        replacement_rule = rand(iter.rng, [rule_id for (rule_id, type) in enumerate(grammar.types) if type == replacement_type])
        children = [rand(iter.rng, iter.extensions[child_type]) for child_type in grammar.childtypes[replacement_rule]]
        replacement = RuleNodeWithRuleCounts(iter, replacement_rule, children)
        replacement = rand(iter.rng, iter.extensions[replacement_type])

        # Replace and return
        return replace_at_path(iter, individual, replacement_path, replacement), :replace

    elseif operation == :insert
        # Select a random node of a type that can be used in recurisve rules.
        node, replacement_path = random_subtree(iter, individual, iter.rules_in_recursive_rules)

        # Select a random recurisve rule of the correct type
        node_type = types[node.rule]
        rule_id = rand(iter.rng, [rule_id for (rule_id, type) in enumerate(types) if iter.recursive_rules[rule_id] && type == node_type])

        # Select a random index where the old node will be placed
        node_index = rand(iter.rng, [index for (index, type) in enumerate(grammar.childtypes[rule_id]) if type == node_type])

        # Fill the other places of the rule with random expressions from the extensions
        children = [index == node_index ? node : rand(iter.rng, iter.extensions[type]) for (index, type) in enumerate(grammar.childtypes[rule_id])]

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
        replacement = rand(iter.rng, [c for c in node.children if types[c.rule] == type])
        return replace_at_path(iter, individual, replacement_path, replacement), :delete
    end
end

