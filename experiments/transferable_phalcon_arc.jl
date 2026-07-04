using Pkg
Pkg.activate("../master-thesis")
Pkg.instantiate()
Pkg.precompile()

using HerbCore, HerbSearch, HerbConstraints, HerbSpecification, HerbBenchmarks, HerbGrammar, HerbInterpret
using StatsBase, RuntimeGeneratedFunctions, DataStructures, SparseArrays, JSON3, JLD2, Random

include("io.jl")
include("../src/lazy_cost_based_bus.jl")
include("../src/genetic_iterator.jl")
include("../src/property_synthesizer.jl")
include("../src/transferable_phalcon.jl")
include("../src/ARC_property_grammar.jl")

repetitions = 1
run = ARGS[1]
path =          "data/transferable_phalcon_arc/transferable_phalcon_arc$(run).json"
property_path = "data/transferable_phalcon_arc/properties/properties$(run).jld2"
store = true

benchmark = HerbBenchmarks.ARC_AGI1
RuntimeGeneratedFunctions.init(benchmark)

# 400 arc training problems
problems_and_complexity = [("problem_67a3c6ac", 1), ("problem_68b16354", 1), ("problem_74dd1130", 1), ("problem_3c9b0459", 1), ("problem_6150a2bd", 1), ("problem_9172f3a0", 1), ("problem_9dfd6313", 1), ("problem_a416b8f3", 1), ("problem_b1948b0a", 1), ("problem_c59eb873", 1), ("problem_c8f0f002", 1), ("problem_d10ecb37", 1), ("problem_d511f180", 1), ("problem_ed36ccf7", 1), ("problem_4c4377d9", 2), ("problem_6d0aefbc", 2), ("problem_6fa7a44f", 2), ("problem_5614dbcf", 2), ("problem_5bd6f4ac", 2), ("problem_5582e5ca", 2), ("problem_8be77c9e", 2), ("problem_c9e6f938", 2), ("problem_2dee498d", 2), ("problem_1cf80156", 3), ("problem_32597951", 3), ("problem_25ff71a9", 3), ("problem_0b148d64", 3), ("problem_1f85a75f", 3), ("problem_23b5c85d", 3), ("problem_9ecd008a", 3), ("problem_ac0a08a4", 3), ("problem_be94b721", 3), ("problem_c909285e", 3), ("problem_f25ffba3", 3), ("problem_c1d99e64", 3), ("problem_b91ae062", 3), ("problem_3aa6fb7a", 3), ("problem_7b7f7511", 3), ("problem_4258a5f9", 3), ("problem_2dc579da", 4), ("problem_28bf18c6", 4), ("problem_3af2c5a8", 4), ("problem_44f52bb0", 4), ("problem_62c24649", 4), ("problem_67e8384a", 4), ("problem_7468f01a", 4), ("problem_662c240a", 4), ("problem_42a50994", 4), ("problem_56ff96f3", 4), ("problem_50cb2852", 4), ("problem_4347f46a", 4), ("problem_46f33fce", 4), ("problem_a740d043", 4), ("problem_a79310a0", 4), ("problem_aabf363d", 4), ("problem_ae4f1146", 4), ("problem_b27ca6d3", 4), ("problem_ce22a75a", 4), ("problem_dc1df850", 4), ("problem_f25fbde4", 4), ("problem_44d8ac46", 4), ("problem_1e0a9b12", 4), ("problem_0d3d703e", 4), ("problem_3618c87e", 4), ("problem_1c786137", 4), ("problem_8efcae92", 5), ("problem_445eab21", 5), ("problem_6f8cd79b", 5), ("problem_2013d3e2", 5), ("problem_41e4d17e", 5), ("problem_9565186b", 5), ("problem_aedd82e4", 5), ("problem_bb43febb", 5), ("problem_e98196ab", 5), ("problem_f76d97a5", 5), ("problem_ce9e57f2", 5), ("problem_22eb0ac0", 5), ("problem_9f236235", 5), ("problem_a699fb00", 5), ("problem_46442a0e", 6), ("problem_7fe24cdd", 6), ("problem_0ca9ddb6", 6), ("problem_543a7ed5", 6), ("problem_0520fde7", 6), ("problem_dae9d2b5", 6), ("problem_8d5021e8", 6), ("problem_928ad970", 6), ("problem_b60334d2", 6), ("problem_b94a9452", 6), ("problem_d037b0a7", 6), ("problem_d0f5fe59", 6), ("problem_e3497940", 6), ("problem_e9afcf9a", 6), ("problem_48d8fb45", 6), ("problem_d406998b", 6), ("problem_5117e062", 6), ("problem_3906de3d", 6), ("problem_00d62c1b", 6), ("problem_7b6016b9", 6), ("problem_67385a82", 6), ("problem_a5313dff", 6), ("problem_ea32f347", 6), ("problem_d631b094", 6), ("problem_10fcaaa3", 6), ("problem_007bbfb7", 7), ("problem_496994bd", 7), ("problem_1f876c06", 7), ("problem_05f2a901", 7), ("problem_39a8645d", 7), ("problem_1b2d62fb", 7), ("problem_90c28cc7", 7), ("problem_b6afb2da", 7), ("problem_b9b7f026", 7), ("problem_ba97ae07", 7), ("problem_c9f8e694", 7), ("problem_d23f8c26", 7), ("problem_d5d6de2d", 7), ("problem_dbc1a6ce", 7), ("problem_ded97339", 7), ("problem_ea786f4a", 7), ("problem_08ed6ac7", 7), ("problem_40853293", 7), ("problem_5521c0d9", 7), ("problem_f8ff0b80", 7), ("problem_85c4e7cd", 7), ("problem_d2abd087", 7), ("problem_017c7c7b", 7), ("problem_363442ee", 7), ("problem_5168d44c", 7), ("problem_e9614598", 7), ("problem_d9fac9be", 7), ("problem_e50d258f", 8), ("problem_810b9b61", 8), ("problem_54d82841", 8), ("problem_60b61512", 3), ("problem_25d8a9c8", 8), ("problem_239be575", 8), ("problem_67a423a3", 8), ("problem_5c0a986e", 8), ("problem_6430c8c4", 8), ("problem_94f9d214", 8), ("problem_a1570a43", 8), ("problem_ce4f8723", 8), ("problem_d13f3404", 8), ("problem_dc433765", 8), ("problem_f2829549", 8), ("problem_fafffa47", 8), ("problem_fcb5c309", 8), ("problem_ff805c23", 8), ("problem_e76a88a6", 8), ("problem_7c008303", 8), ("problem_7f4411dc", 8), ("problem_b230c067", 8), ("problem_e8593010", 8), ("problem_6d75e8bb", 8), ("problem_3f7978a0", 8), ("problem_1190e5a7", 8), ("problem_6e02f1e3", 8), ("problem_a61f2674", 8), ("problem_fcc82909", 9), ("problem_72ca375d", 9), ("problem_253bf280", 9), ("problem_694f12f3", 9), ("problem_1f642eb9", 9), ("problem_31aa019c", 9), ("problem_27a28665", 9), ("problem_7ddcd7ec", 9), ("problem_3bd67248", 9), ("problem_73251a56", 9), ("problem_25d487eb", 9), ("problem_8f2ea7aa", 9), ("problem_b8825c91", 9), ("problem_cce03e0d", 9), ("problem_d364b489", 9), ("problem_a5f85a15", 9), ("problem_3ac3eb23", 9), ("problem_444801d8", 9), ("problem_22168020", 9), ("problem_6e82a1ae", 9), ("problem_b2862040", 9), ("problem_868de0fa", 9), ("problem_681b3aeb", 9), ("problem_8e5a5113", 9), ("problem_025d127b", 9), ("problem_2281f1f4", 9), ("problem_cf98881b", 9), ("problem_d4f3cd78", 9), ("problem_bda2d7a6", 9), ("problem_137eaa0f", 9), ("problem_6455b5f5", 9), ("problem_b8cdaf2b", 9), ("problem_bd4472b8", 9), ("problem_4be741c5", 9), ("problem_bbc9ae5d", 9), ("problem_d90796e8", 9), ("problem_2c608aff", 9), ("problem_f8b3ba0a", 10), ("problem_80af3007", 10), ("problem_83302e8f", 10), ("problem_1fad071e", 10), ("problem_11852cab", 10), ("problem_3428a4f5", 10), ("problem_178fcbfb", 10), ("problem_3de23699", 10), ("problem_54d9e175", 10), ("problem_5ad4f10b", 10), ("problem_623ea044", 10), ("problem_6b9890af", 10), ("problem_794b24be", 10), ("problem_88a10436", 10), ("problem_88a62173", 10), ("problem_890034e9", 10), ("problem_99b1bc43", 10), ("problem_a9f96cdd", 10), ("problem_af902bf9", 10), ("problem_b548a754", 10), ("problem_bdad9b1f", 10), ("problem_c3e719e8", 10), ("problem_de1cd16c", 10), ("problem_d8c310e9", 10), ("problem_a3325580", 10), ("problem_8eb1be9a", 10), ("problem_321b1fc6", 10), ("problem_1caeab9d", 10), ("problem_77fdfe62", 10), ("problem_c0f76784", 10), ("problem_1b60fb0c", 11), ("problem_ddf7fa4f", 10), ("problem_47c1f68c", 10), ("problem_6c434453", 10), ("problem_23581191", 10), ("problem_c8cbb738", 10), ("problem_3eda0437", 10), ("problem_dc0a314f", 10), ("problem_d4469b4b", 10), ("problem_6ecd11f4", 11), ("problem_760b3cac", 11), ("problem_c444b776", 10), ("problem_d4a91cb9", 11), ("problem_eb281b96", 11), ("problem_ff28f65a", 10), ("problem_7e0986d6", 10), ("problem_09629e4f", 7), ("problem_a85d4709", 11), ("problem_feca6190", 11), ("problem_a68b268e", 12), ("problem_beb8660c", 12), ("problem_913fb3ed", 9), ("problem_0962bcdd", 12), ("problem_3631a71a", 13), ("problem_05269061", 13), ("problem_95990924", 10), ("problem_e509e548", 13), ("problem_d43fd935", 13), ("problem_db3e9e38", 13), ("problem_e73095fd", 13), ("problem_1bfc4729", 12), ("problem_93b581b8", 12), ("problem_9edfc990", 7), ("problem_a65b410d", 11), ("problem_7447852a", 13), ("problem_97999447", 14), ("problem_91714a58", 14), ("problem_a61ba2ce", 14), ("problem_8e1813be", 14), ("problem_bc1d5164", 14), ("problem_ce602527", 14), ("problem_5c2c9af4", 15), ("problem_75b8110e", 15), ("problem_941d9a10", 15), ("problem_c3f564a4", 15), ("problem_1a07d186", 15), ("problem_d687bc17", 15), ("problem_9af7a82c", 15), ("problem_6e19193c", 15), ("problem_ef135b50", 15), ("problem_cbded52d", 15), ("problem_8a004b2b", 15), ("problem_e26a3af2", 15), ("problem_6cf79266", 15), ("problem_a87f7484", 13), ("problem_4093f84a", 14), ("problem_ba26e723", 8), ("problem_4612dd53", 16), ("problem_29c11459", 16), ("problem_963e52fc", 16), ("problem_ae3edfdc", 16), ("problem_1f0c79e5", 16), ("problem_56dc2b01", 17), ("problem_e48d4e1a", 17), ("problem_6773b310", 17), ("problem_780d0b14", 18), ("problem_2204b7a8", 18), ("problem_d9f24cd1", 18), ("problem_b782dc8a", 18), ("problem_673ef223", 18), ("problem_f5b8619d", 6), ("problem_f8c80d96", 18), ("problem_ecdecbb3", 18), ("problem_e5062a87", 18), ("problem_a8d7556c", 18), ("problem_4938f0c2", 18), ("problem_834ec97d", 18), ("problem_846bdb03", 18), ("problem_90f3ed37", 18), ("problem_8403a5d5", 19), ("problem_91413438", 19), ("problem_539a4f51", 19), ("problem_5daaa586", 19), ("problem_3bdb4ada", 19), ("problem_ec883f72", 19), ("problem_2bee17df", 20), ("problem_e8dc4411", 20), ("problem_e40b9e2f", 20), ("problem_29623171", 20), ("problem_a2fd1cf0", 20), ("problem_b0c4d837", 20), ("problem_8731374e", 20), ("problem_272f95fa", 20), ("problem_db93a21d", 20), ("problem_53b68214", 20), ("problem_d6ad076f", 20), ("problem_6cdd2623", 13), ("problem_a3df8b1e", 21), ("problem_8d510a79", 18), ("problem_cdecee7f", 21), ("problem_3345333e", 14), ("problem_b190f7f5", 13), ("problem_caa06a1f", 22), ("problem_e21d9049", 22), ("problem_d89b689b", 12), ("problem_746b3537", 10), ("problem_63613498", 12), ("problem_06df4c85", 22), ("problem_f9012d9b", 22), ("problem_4522001f", 22), ("problem_a48eeaf7", 11), ("problem_eb5a1d5d", 9), ("problem_e179c5f4", 23), ("problem_228f6490", 23), ("problem_995c5fa3", 23), ("problem_d06dbe63", 23), ("problem_36fdfd69", 14), ("problem_0a938d79", 17), ("problem_045e512c", 15), ("problem_82819916", 22), ("problem_99fa7670", 24), ("problem_72322fa7", 24), ("problem_855e0971", 20), ("problem_a78176bb", 24), ("problem_952a094c", 14), ("problem_6d58a25d", 18), ("problem_6aa20dc0", 25), ("problem_e6721834", 25), ("problem_447fd412", 25), ("problem_2bcee788", 26), ("problem_776ffc46", 17), ("problem_f35d900a", 20), ("problem_0dfd9992", 26), ("problem_29ec7d0e", 26), ("problem_36d67576", 26), ("problem_98cf29f8", 18), ("problem_469497ad", 18), ("problem_39e1d7f9", 30), ("problem_484b58aa", 27), ("problem_3befdf3e", 26), ("problem_9aec4887", 22), ("problem_49d1d64f", 17), ("problem_57aa92db", 29), ("problem_aba27056", 30), ("problem_f1cefba8", 30), ("problem_1e32b0e9", 31), ("problem_28e73c20", 31), ("problem_4c5c2cf0", 34), ("problem_508bd3b6", 32), ("problem_6d0160f0", 32), ("problem_f8a8fe49", 32), ("problem_d07ae81c", 32), ("problem_6a1e5592", 33), ("problem_0e206a2e", 35), ("problem_d22278a0", 35), ("problem_4290ef0e", 45), ("problem_50846271", 39), ("problem_b527c5c6", 40), ("problem_150deff5", 40), ("problem_b7249182", 40), ("problem_9d9215db", 41), ("problem_6855a6e4", 41), ("problem_264363fd", 44), ("problem_7df24a62", 45), ("problem_f15e1fac", 45), ("problem_234bbc79", 43), ("problem_22233c11", 12), ("problem_2dd70a9a", 47), ("problem_a64e4611", 48), ("problem_7837ac64", 38), ("problem_a8c38be5", 28), ("problem_b775ac94", 57), ("problem_97a05b5b", 60), ("problem_3e980e27", 37)]
problems_and_complexity = shuffle(MersenneTwister(run), problems_and_complexity)
problems_and_complexity = sort(problems_and_complexity, by = last)
task_names = first.(problems_and_complexity)

problems = [getfield(benchmark, Symbol(name)) for name in task_names]
grammar = benchmark.grammar_hodel

stored_properties = load_properties(property_path)

for problem in problems
    performed_repetitions(path, problem.name) > 0 && continue

    max_length = 2 * maximum([max(maximum(length, values(io.in)), length(io.out)) for io in problem.spec])
    rule_cost_func = r -> r isa Expr && !(r.args[1] in [:objects, :asgrid])
    rule_costs = Int[rule_cost_func(r) for r in grammar.rules]

    iterator = GeneticIterator(grammar, :Start,
        benchmark = benchmark,
        problem = problem,
        cost = _ -> 0,
        population_size = 20,
        candidate_pool_size = 10000,
        max_generations_without_improvement = 10,
        max_extension_size = 1,
        max_initial_population_size = 1,
        max_size = 50,
        rule_costs = rule_costs,
        prune_node_by_output = (io, y) -> length(y) > max_length,
    )

    result = transferable_phalcon(
        iterator = iterator,
        stored_properties = stored_properties,
        max_number_of_iterations = 20,
        property_types = [:Grid, :Objects, :Object, :Indices, :IntContainer, :IntegerTuple, :Integer, :Boolean],
        max_property_cost = 3,
        grammar_to_property_grammar = _ -> _grammar_to_property_grammar(property_grammar_hodel),
        rule_cost_func = rule_cost_func,
        prune_node_by_output = y -> length(y) > max_length,
        verbose = false,
        timeout = 60*30,
    )

    if store
        append_result(path, result)
        store_properties(property_path, stored_properties)
    else
        println()
        @show result
    end
end