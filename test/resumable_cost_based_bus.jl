@testset "Resumable cost-based bus matches eager enumeration" begin
    grammar = @csgrammar begin
        Start = _arg_1
        Start = 1
        Start = 1 + 0
        Start = nothing
        Start = Start + Start
        Flag = Start > Start
        Label = string(Flag)
    end
    addconstraint!(grammar, HerbConstraints.ForbiddenSequence([2]))
    examples = [IOExample(Dict{Symbol,Any}(:_arg_1 => x), x) for x in (2, 3)]
    interpreter = HerbInterpret.make_output_interpreter(grammar; target_module=Main)
    output = (rule, children) -> interpreter(rule, children, examples)
    costs = [0, 0, 0, 0, 2, 1, 0]

    # Reorder the exposed types and leave some types available only as children.
    for types in ([:Label, :Start, :Flag], [:Flag, :Label], [:Start])
        args = (grammar, types, 4, costs, output, isnothing)
        eager = LazyCostBasedBus(args...)
        lazy = ResumableCostBasedBus(args...)
        expected = [(RuleNode(p), p.outputs) for p in Iterators.filter(_ -> true, eager)]
        actual = [(RuleNode(p), p.outputs) for p in lazy]
        @test !isempty(expected)
        @test isequal(actual, expected)
        @test all(Phalcon._satisfies_constraints(grammar, p) for p in lazy)
    end
end

@testset "Resumable cost-based bus evaluates parents on demand" begin
    grammar = @csgrammar begin
        Start = tuple(Leaf, Leaf)
        Leaf = |(1:10)
    end
    function counted_bus(Bus)
        parent_calls = Ref(0)
        function output(rule, children)
            rule != 1 && return [rule]
            parent_calls[] += 1
            return [(only(children[1]), only(children[2]))]
        end
        return Bus(grammar, [:Start], 3, ones(Int, 11), output, _ -> false), parent_calls
    end

    eager, eager_calls = counted_bus(LazyCostBasedBus)
    eager_first = first(eager)
    @test eager_calls[] == 100

    lazy, lazy_calls = counted_bus(ResumableCostBasedBus)
    first_program, state = iterate(lazy)
    @test lazy_calls[] == 1
    @test RuleNode(first_program) == RuleNode(eager_first)
    second_program, state = iterate(lazy, state)
    @test lazy_calls[] == 2

    eager_bucket = get_programs(eager, :Start, 3)
    lazy_bucket = get_programs(lazy, :Start, 3)
    @test lazy_calls[] == 100
    @test lazy_bucket[1] === first_program
    @test lazy_bucket[2] === second_program
    @test RuleNode.(lazy_bucket) == RuleNode.(eager_bucket)
    @test getfield.(lazy_bucket, :outputs) == getfield.(eager_bucket, :outputs)
    third_program, _ = iterate(lazy, state)
    @test third_program === lazy_bucket[3]
    @test lazy_calls[] == 100

    expired = ResumableCostBasedBus(grammar, [:Start], 3, ones(Int, 11),
        (_, _) -> error("must not evaluate"), _ -> false; deadline=Phalcon._search_time() - 1)
    @test_throws Phalcon.SearchTimeout iterate(expired)
    @test_throws Phalcon.SearchTimeout get_programs(expired, :Start, 3)
end
