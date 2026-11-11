@testset "Selective Contains products and child-pool completion" begin
    grammar = @csgrammar begin
        Start = tuple(Leaf, Leaf)
        Leaf = _arg_out
        Leaf = 1
        Leaf = 2
        Wrap = identity(Start)
    end
    addconstraint!(grammar, HerbConstraints.Contains(2))

    function run_bus(Bus, types, max_cost)
        parent_calls = Ref(0)
        function output(rule, children)
            if rule == 1
                parent_calls[] += 1
                return [(only(children[1]), only(children[2]))]
            end
            rule == 5 && return only(children)
            return [rule]
        end
        bus = Bus(grammar, types, max_cost, [1, 1, 1, 1, 0], output, _ -> false)
        return [(RuleNode(p), p.outputs) for p in bus], parent_calls[]
    end

    for (types, max_cost, expected_calls) in (([:Start], 3, 5), ([:Start], 4, 9),
            ([:Start, :Wrap], 3, 9), ([:Wrap, :Start], 3, 9))
        expected, original_calls = run_bus(ResumableCostBasedBus, types, max_cost)
        actual, selective_calls = run_bus(SelectiveContainsCostBasedBus, types, max_cost)
        @test !isempty(expected)
        @test isequal(actual, expected)
        @test original_calls == 9
        @test selective_calls == expected_calls
    end
end

@testset "Selective Contains deduplicates within each class" begin
    grammar = @csgrammar begin
        Start = 1
        Start = _arg_out
        Start = identity(Start)
    end
    addconstraint!(grammar, HerbConstraints.Contains(2))
    args = (grammar, [:Start], 2, [0, 0, 1], (_, _) -> [1], _ -> false)
    @test isempty(collect(ResumableCostBasedBus(args...)))
    @test RuleNode.(collect(SelectiveContainsCostBasedBus(args...))) == [RuleNode(2)]
end
