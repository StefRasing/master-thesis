@testset "Contains-aware enumeration preserves program order" begin
    grammar = @csgrammar begin
        Start = tuple(Leaf, Leaf)
        Leaf = _arg_out
        Leaf = 1
        Leaf = 2
        Wrap = identity(Start)
    end
    addconstraint!(grammar, HerbConstraints.Contains(2))

    function enumerate(Bus, types, max_cost; prune=_ -> false)
        calls = Int[]
        function output(rule, children)
            push!(calls, rule)
            rule == 1 && return [(only(children[1]), only(children[2]))]
            rule == 5 && return only(children)
            return [rule]
        end
        bus = Bus(grammar, types, max_cost, [1, 1, 1, 1, 0], output, prune)
        return [(RuleNode(p), p.outputs) for p in bus], count(==(1), calls)
    end

    expected, eager_calls = enumerate(ResumableCostBasedBus, [:Start], 3)
    actual, contains_calls = enumerate(ContainsCostBasedBus, [:Start], 3)
    @test length(expected) == 5
    @test isequal(actual, expected)
    @test eager_calls == 9
    @test contains_calls == 7

    # On cost advancement, the deferred tail is completed.
    expected, eager_calls = enumerate(ResumableCostBasedBus, [:Start], 4)
    actual, contains_calls = enumerate(ContainsCostBasedBus, [:Start], 4)
    @test isequal(actual, expected)
    @test contains_calls == eager_calls == 9

    # A zero-cost parent may need the full pool within the same cost.
    for types in ([:Start, :Wrap], [:Wrap, :Start], [:Wrap]), prune in (_ -> false, ==(3))
        expected, eager_calls = enumerate(ResumableCostBasedBus, types, 3; prune)
        actual, contains_calls = enumerate(ContainsCostBasedBus, types, 3; prune)
        @test !isempty(expected)
        @test isequal(actual, expected)
        @test contains_calls == eager_calls
    end
end

@testset "Contains-aware enumeration preserves first-seen duplicates" begin
    grammar = @csgrammar begin
        Start = 1
        Start = _arg_out
        Start = identity(Start)
    end
    addconstraint!(grammar, HerbConstraints.Contains(2))
    args = (grammar, [:Start], 2, [0, 0, 1], (_, _) -> [1], _ -> false)
    @test isempty(collect(ResumableCostBasedBus(args...)))
    @test isempty(collect(ContainsCostBasedBus(args...)))
end
