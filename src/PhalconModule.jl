"""
Search algorithms for the thesis experiments.

Load with `include("src/PhalconModule.jl"); using .Phalcon`.
Benchmark DSL modules and problem specifications are supplied by callers.
"""
module Phalcon

using Random
using SparseArrays
using DataStructures: DefaultDict, OrderedDict
using StatsBase: sample, Weights
using HerbCore
using HerbGrammar
using HerbConstraints
using HerbSearch
import HerbInterpret

export GeneticIterator, LazyCostBasedBus, Property,
       initialize!, find_solution, local_optimum_outputs, update_cost_function,
       find_property!, phalcon, levenshtein, hamming_distance

include("deadline.jl")
include("lazy_cost_based_bus.jl")
include("genetic_iterator.jl")
include("property_synthesizer.jl")
include("phalcon.jl")
include("heuristics.jl")

end
