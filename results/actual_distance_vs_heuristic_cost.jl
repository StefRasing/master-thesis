using HerbCore, HerbSearch, HerbConstraints, HerbSpecification, HerbBenchmarks, HerbGrammar
using JSON, MLStyle, DataStructures, Dates
using Plots, StatsBase

include("../experiments/utils/string_functions.jl")
include("../src/property_based_neighborhood_iterator.jl")

benchmark = HerbBenchmarks.PBE_SLIA_Track_2019
problem = benchmark.problem_create_email_address_with_name_and_domain
grammar = benchmark.grammar_create_email_address_with_name_and_domain

property_grammar = deepcopy(grammar)
merge_grammars!(property_grammar, @cfgrammar begin
    ntInt = 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9
    ntBool = ntString == ntString
    ntBool = ntInt == ntInt
    ntBool = ntInt <= ntInt
    ntBool = ntInt < ntInt
end)
add_rule!(property_grammar, Expr(:(=), :ntString, :_arg_out))

grammar_tags = get_relevant_tags(property_grammar)

iter = PropertyBasedNeighborhoodIterator(grammar, :ntString, problem, (p, x) -> interpret_sygus(p, grammar_tags, x), 1, Tuple{AbstractRuleNode, Any}[])
Base.iterate(iter)

data = JSON.parsefile("data/SyGuS strings-2026-03-17_15:02:54-max_properties=10.json")
filter!(x -> x["specification"]["problem"]["name"] == "problem_create_email_address_with_name_and_domain", data)
solution = data[1]["solution"]["rulenode"]
solution_depth = data[1]["solution"]["depth"]
solution_size = data[1]["solution"]["size"]

neighbors = DefaultDict(() -> Set())
unexpanded_programs = Set(collect(BFSIterator(grammar, :ntString, max_size=1)))
expanded_programs = Set()

# solution = "8{8{3,7},4}"
# solution_depth = 3
# solution_size = 5

function get_actual_distances_to_solution()
    while length(unexpanded_programs) > 0
        program = pop!(unexpanded_programs)
        push!(expanded_programs, program)

        neighborhood_of_program = neighborhood(iter, program)
        filter!(n -> depth(n) <= solution_depth && length(n) <= solution_size, neighborhood_of_program)

        union!(neighbors["$program"], ["$n" for n in neighborhood_of_program])

        for neighbor in neighborhood_of_program
            push!(neighbors["$neighbor"], "$program")

            if !(neighbor in expanded_programs)
                push!(unexpanded_programs, neighbor)
            end
        end
    end

    program_to_distance = Dict(solution => 0)
    current_horizon = [solution]

    while length(current_horizon) > 0
        next_horizon = []

        for program in current_horizon
            distance = program_to_distance[program]
            
            for neighbor in neighbors[program]
                if !haskey(program_to_distance, neighbor)
                    program_to_distance[neighbor] = distance + 1
                    push!(next_horizon, neighbor)
                end
            end
        end

        current_horizon = next_horizon
    end

    return program_to_distance
end

@timed program_to_actual_distance = get_actual_distances_to_solution()

function string_to_rulenode(s)
    Base.eval(@__MODULE__, Meta.parse("@rulenode " * s))
end

for properties in data[1]["heuristic"]["properties"]
    rulenode_string = properties["rulenode"]
    property = string_to_rulenode(rulenode_string)
    target_values = [interpret_sygus(property, grammar_tags, (io.in[:_arg_out] = io.out; io.in)) for io in problem.spec]
    push!(iter.selected_properties, (property, target_values))
end

data_points = []

for (program_string, actual_distance) in program_to_actual_distance
    program = string_to_rulenode(program_string)
    heuristic_distance = heuristic_cost(iter, program)

    if heuristic_distance != typemax(Int)
        push!(data_points, (actual_distance, heuristic_distance))
    end
end

x = first.(data_points)
y = last.(data_points)

ϵ = 0.1  # jitter strength
x_jitter = x .+ ϵ .* randn(length(x))
y_jitter = y .+ ϵ .* randn(length(y))

scatter(x_jitter, y_jitter, label="")
title!("Actual distance vs heuristic cost")
xlabel!("Actual distance")
ylabel!("Heuristic cost")