using Random

@testset "Unicode distance contracts" begin
    for (a, b, distance) in (("", "", 0), ("", "é🙂", 2),
        ("éa", "ea", 1), ("🙂a", "🙂b", 1), ("猫", "犬", 1),
        ("kitten", "sitting", 3), ("é", "é", 0))
        @test levenshtein(a, b) == distance
        @test levenshtein(b, a) == distance
        @test levenshtein(SubString("x" * a, 2), b) == distance
    end
end

# A small, typed grammar exercises operators without benchmark data or globals.
function contract_iterator(; population_size=3)
    grammar = @csgrammar begin
        Start = 1
        Start = 2
        Start = Start + Start
        Flag = Start > Start
        Flag = true
    end
    iter = GeneticIterator(grammar, :Start; rng=Xoshiro(42),
        problem=(name="contracts", spec=[IOExample(Dict{Symbol,Any}(), 99)],),
        benchmark=Main, cost=_ -> 1, rule_costs=ones(Int, 5), population_size)
    initialize!(iter)
    empty!(iter.population)
    iter.programs_evaluated = 0
    return iter
end

@testset "Population ordering, bounds and observational deduplication" begin
    iter = contract_iterator()
    node(r, children...) = RuleNodeWithRuleCounts(iter, r, RuleNodeWithRuleCounts[children...])
    one, two = node(1), node(2)
    three = node(3, one, two)
    four = node(3, two, two)
    long_two = node(3, one, one)
    individual(p, cost) = Individual(p, cost, nothing, nothing, nothing, nothing)
    add(p, cost=1) = Phalcon.add_to_population!(iter, individual(p, cost))
    add(three); add(four); add(long_two)
    @test length(iter.population) == 3
    add(two) # Shorter equivalent must move ahead of the three-node programs.
    @test issorted(iter.population)
    @test first(iter.population).program === two
    @test count(ind -> ind.program.outputs == [2], iter.population) == 1
    add(two)
    @test length(iter.population) == 3
    add(one, 0)
    @test issorted(iter.population)
    @test first(iter.population).program === one
    @test length(iter.population) == iter.population_size
    before = copy(iter.population)
    add(four, Inf)
    add(four, 10)
    @test iter.population == before
    @test iter.programs_evaluated == 8 # Includes rejected candidates.
    empty!(iter.population)
    @test isempty(local_optimum_outputs(iter))
    @test_throws ArgumentError Phalcon.combine!(iter)
    @test_throws ArgumentError find_solution(iter)
end

# Recompute counts and outputs from the tree rather than trusting its caches.
function check_contract_tree(iter, tree)
    grammar = iter.solver.grammar
    counts = zeros(Int, length(grammar.rules))
    function visit(node)
        counts[node.rule] += 1
        @test length(node.children) == length(grammar.childtypes[node.rule])
        for (child, type) in zip(node.children, grammar.childtypes[node.rule])
            @test grammar.types[child.rule] == type
            visit(child)
        end
    end
    visit(tree)
    @test collect(tree.rule_counts) == counts
    @test length(tree) == sum(counts)
    rebuilt = RuleNodeWithRuleCounts(iter, RuleNode(tree))
    @test tree.outputs == rebuilt.outputs
end

@testset "Mutation and crossover preserve tree contracts" begin
    iter = contract_iterator()
    parent = RuleNodeWithRuleCounts(iter, RuleNode(3, [RuleNode(1), RuleNode(2)]))
    snapshot = deepcopy(parent)
    operations = Set{Symbol}()
    for _ in 1:100
        child, operation = Phalcon.mutate(iter, parent)
        push!(operations, operation)
        @test iter.solver.grammar.types[child.rule] == :Start
        check_contract_tree(iter, child)
        crossed, (replacement, removed) = Phalcon.crossover(iter, child, parent)
        @test iter.solver.grammar.types[replacement.rule] == iter.solver.grammar.types[removed.rule]
        check_contract_tree(iter, crossed)
    end
    @test operations == Set([:replace, :insert, :delete])
    @test RuleNode(parent) == RuleNode(snapshot)
    @test parent.outputs == snapshot.outputs
    @test parent.rule_counts == snapshot.rule_counts
end

@testset "Deadline cancellation and exception propagation" begin
    iter = contract_iterator()
    parent = RuleNodeWithRuleCounts(iter, RuleNode(3, [RuleNode(1), RuleNode(2)]))
    push!(iter.population, Individual(iter, parent))
    before = copy(iter.population)
    evaluated = iter.programs_evaluated
    @test_throws Phalcon.SearchTimeout Phalcon.combine!(iter; deadline=Phalcon._search_time() - 1)
    @test iter.population == before
    @test iter.programs_evaluated == evaluated
    @test_throws Phalcon.SearchTimeout update_cost_function(iter, _ -> 2; deadline=Phalcon._search_time() - 1)
    # Only the internal cancellation signal should become an unsolved result.
    iter = contract_iterator()
    iter.cost = _ -> throw(DomainError(:sentinel))
    @test_throws DomainError phalcon(iterator=iter, timeout=60,
        property_types=[:Start], max_property_cost=1, rule_cost_func=_ -> 1)
end
