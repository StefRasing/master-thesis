using Test, SparseArrays, DataStructures, StatsBase
using HerbCore, HerbGrammar, HerbConstraints, HerbSearch, HerbSpecification, HerbInterpret
include("../src/PhalconModule.jl")
using .Phalcon
using .Phalcon: CachedRuleNode, RuleNodeWithRuleCounts, Individual,
    get_programs, assemble, _hash_outputs, interp, outputs_to_cost

