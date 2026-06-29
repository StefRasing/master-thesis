using JSON3
using Plots
using Statistics
using HerbBenchmarks

struct Result
    problem_name::String
    solved::Bool
    execution_time::Float64
    programs_enumerated::Int64
end

function step_align(best_x, best_y, worst_x, worst_y)
    x = sort(unique(vcat(best_x, worst_x)))

    function step_values(xs, ys, xgrid)
        result = similar(xgrid, eltype(ys))
        j = 1
        current = ys[1]

        for (i, x) in enumerate(xgrid)
            while j < length(xs) && xs[j + 1] <= x
                j += 1
                current = ys[j]
            end
            result[i] = current
        end

        result
    end

    return x, step_values(best_x, best_y, x), step_values(worst_x, worst_y, x)
end

function aggregate_best_worst(results, field::Symbol)
    grouped = Dict{String, Vector{Result}}()

    for r in results
        push!(get!(grouped, r.problem_name, Result[]), r)
    end

    best = Float64[]
    worst = Float64[]

    for (_, rs) in grouped
        solved_rs = filter(r -> r.solved, rs)
        unsolved_rs = filter(r -> !r.solved, rs)
        vals_solved = getfield.(solved_rs, field)

        # Best: minimum of solved if any solved§
        if !isempty(solved_rs)
            push!(best, minimum(vals_solved))
        end

        # Worst: maximum of solved if no unsolved
        if isempty(unsolved_rs)
            push!(worst, maximum(vals_solved))
        end
    end

    return best, worst
end

function load_results(file)
    data = JSON3.read(read(file, String))

    if occursin("strings", file)
        string_to_string_tasks = ["problem_11440431", "problem_11604909", "problem_17212077", "problem_2171308", "problem_25239569", "problem_28627624_1", "problem_30732554", "problem_31753108", "problem_33619752", "problem_34801680", "problem_35744094", "problem_36462127", "problem_38664547", "problem_38871714", "problem_39060015", "problem_41503046", "problem_43120683", "problem_43606446", "problem_bikes", "problem_change_negative_numbers_to_positive", "problem_clean_and_reformat_telephone_numbers", "problem_dr_name", "problem_exceljet2", "problem_exceljet3", "problem_exceljet4", "problem_extract_word_containing_specific_text", "problem_extract_word_that_begins_with_specific_character", "problem_firstname", "problem_get_domain_name_from_url", "problem_get_first_name_from_name", "problem_get_first_word", "problem_get_last_line_in_cell", "problem_get_last_name_from_name", "problem_get_last_name_from_name_with_comma", "problem_get_last_word", "problem_get_middle_name_from_full_name", "problem_initials", "problem_lastname", "problem_phone", "problem_phone_1", "problem_phone_10", "problem_phone_2", "problem_phone_3", "problem_phone_4", "problem_phone_5", "problem_phone_6", "problem_phone_7", "problem_phone_8", "problem_phone_9", "problem_remove_file_extension_from_filename", "problem_remove_leading_and_trailing_spaces_from_text", "problem_remove_text_by_matching", "problem_remove_text_by_position", "problem_replace_one_character_with_another", "problem_stackoverflow1", "problem_stackoverflow10", "problem_stackoverflow11", "problem_stackoverflow2", "problem_stackoverflow3", "problem_stackoverflow4", "problem_stackoverflow5", "problem_stackoverflow6", "problem_stackoverflow8", "problem_stackoverflow9", "problem_strip_html_from_text_or_numbers", "problem_strip_non_numeric_characters", "problem_strip_numeric_characters_from_cell"]
        
        return [
            Result(
                x.problem_name,
                x.solved,
                x.execution_time,
                x.programs_enumerated
            )
            for x in data if x.problem_name in string_to_string_tasks
        ]
    end

    # tasks = ["problem_67a3c6ac", "problem_68b16354", "problem_74dd1130", "problem_3c9b0459", "problem_6150a2bd", "problem_9172f3a0", "problem_9dfd6313", "problem_a416b8f3", "problem_b1948b0a", "problem_c59eb873", "problem_c8f0f002", "problem_d10ecb37", "problem_d511f180", "problem_ed36ccf7", "problem_4c4377d9", "problem_6d0aefbc", "problem_6fa7a44f", "problem_5614dbcf", "problem_5bd6f4ac", "problem_5582e5ca", "problem_8be77c9e", "problem_c9e6f938", "problem_2dee498d", "problem_1cf80156", "problem_32597951", "problem_25ff71a9", "problem_0b148d64", "problem_1f85a75f", "problem_23b5c85d", "problem_9ecd008a", "problem_ac0a08a4", "problem_be94b721", "problem_c909285e", "problem_f25ffba3", "problem_c1d99e64", "problem_b91ae062", "problem_3aa6fb7a", "problem_7b7f7511", "problem_4258a5f9", "problem_2dc579da", "problem_28bf18c6", "problem_3af2c5a8", "problem_44f52bb0", "problem_62c24649", "problem_67e8384a", "problem_7468f01a", "problem_662c240a", "problem_42a50994", "problem_56ff96f3", "problem_50cb2852", "problem_4347f46a", "problem_46f33fce", "problem_a740d043", "problem_a79310a0", "problem_aabf363d", "problem_ae4f1146", "problem_b27ca6d3", "problem_ce22a75a", "problem_dc1df850", "problem_f25fbde4", "problem_44d8ac46", "problem_1e0a9b12", "problem_0d3d703e", "problem_3618c87e", "problem_1c786137", "problem_8efcae92", "problem_445eab21", "problem_6f8cd79b", "problem_2013d3e2", "problem_41e4d17e", "problem_9565186b", "problem_aedd82e4", "problem_bb43febb", "problem_e98196ab", "problem_f76d97a5", "problem_ce9e57f2", "problem_22eb0ac0", "problem_9f236235", "problem_a699fb00", "problem_46442a0e", "problem_7fe24cdd", "problem_0ca9ddb6", "problem_543a7ed5", "problem_0520fde7", "problem_dae9d2b5", "problem_8d5021e8", "problem_928ad970", "problem_b60334d2", "problem_b94a9452", "problem_d037b0a7", "problem_d0f5fe59", "problem_e3497940", "problem_e9afcf9a", "problem_48d8fb45", "problem_d406998b", "problem_5117e062", "problem_3906de3d", "problem_00d62c1b", "problem_7b6016b9", "problem_67385a82", "problem_a5313dff", "problem_ea32f347", "problem_d631b094", "problem_10fcaaa3", "problem_007bbfb7", "problem_496994bd", "problem_1f876c06", "problem_05f2a901", "problem_39a8645d", "problem_1b2d62fb", "problem_90c28cc7", "problem_b6afb2da", "problem_b9b7f026", "problem_ba97ae07", "problem_c9f8e694", "problem_d23f8c26", "problem_d5d6de2d", "problem_dbc1a6ce", "problem_ded97339", "problem_ea786f4a", "problem_08ed6ac7", "problem_40853293", "problem_5521c0d9", "problem_f8ff0b80", "problem_85c4e7cd", "problem_d2abd087", "problem_017c7c7b", "problem_363442ee", "problem_5168d44c", "problem_e9614598", "problem_d9fac9be", "problem_e50d258f", "problem_810b9b61", "problem_54d82841", "problem_60b61512", "problem_25d8a9c8", "problem_239be575", "problem_67a423a3", "problem_5c0a986e", "problem_6430c8c4", "problem_94f9d214", "problem_a1570a43", "problem_ce4f8723", "problem_d13f3404", "problem_dc433765", "problem_f2829549", "problem_fafffa47", "problem_fcb5c309", "problem_ff805c23", "problem_e76a88a6", "problem_7c008303", "problem_7f4411dc", "problem_b230c067", "problem_e8593010", "problem_6d75e8bb", "problem_3f7978a0", "problem_1190e5a7", "problem_6e02f1e3", "problem_a61f2674", "problem_fcc82909", "problem_72ca375d", "problem_253bf280", "problem_694f12f3", "problem_1f642eb9", "problem_31aa019c", "problem_27a28665", "problem_7ddcd7ec", "problem_3bd67248", "problem_73251a56", "problem_25d487eb", "problem_8f2ea7aa", "problem_b8825c91", "problem_cce03e0d", "problem_d364b489", "problem_a5f85a15", "problem_3ac3eb23", "problem_444801d8", "problem_22168020", "problem_6e82a1ae", "problem_b2862040", "problem_868de0fa", "problem_681b3aeb", "problem_8e5a5113", "problem_025d127b", "problem_2281f1f4", "problem_cf98881b", "problem_d4f3cd78", "problem_bda2d7a6", "problem_137eaa0f", "problem_6455b5f5", "problem_b8cdaf2b", "problem_bd4472b8", "problem_4be741c5", "problem_bbc9ae5d", "problem_d90796e8", "problem_2c608aff", "problem_f8b3ba0a", "problem_80af3007", "problem_83302e8f", "problem_1fad071e", "problem_11852cab", "problem_3428a4f5", "problem_178fcbfb", "problem_3de23699", "problem_54d9e175", "problem_5ad4f10b", "problem_623ea044", "problem_6b9890af", "problem_794b24be", "problem_88a10436", "problem_88a62173", "problem_890034e9", "problem_99b1bc43", "problem_a9f96cdd", "problem_af902bf9", "problem_b548a754", "problem_bdad9b1f", "problem_c3e719e8", "problem_de1cd16c", "problem_d8c310e9", "problem_a3325580", "problem_8eb1be9a", "problem_321b1fc6", "problem_1caeab9d", "problem_77fdfe62", "problem_c0f76784", "problem_1b60fb0c", "problem_ddf7fa4f", "problem_47c1f68c", "problem_6c434453", "problem_23581191", "problem_c8cbb738", "problem_3eda0437", "problem_dc0a314f", "problem_d4469b4b", "problem_6ecd11f4", "problem_760b3cac", "problem_c444b776", "problem_d4a91cb9", "problem_eb281b96", "problem_ff28f65a", "problem_7e0986d6", "problem_09629e4f", "problem_a85d4709", "problem_feca6190", "problem_a68b268e", "problem_beb8660c", "problem_913fb3ed", "problem_0962bcdd", "problem_3631a71a", "problem_05269061", "problem_95990924", "problem_e509e548", "problem_d43fd935", "problem_db3e9e38", "problem_e73095fd", "problem_1bfc4729", "problem_93b581b8", "problem_9edfc990", "problem_a65b410d", "problem_7447852a", "problem_97999447", "problem_91714a58", "problem_a61ba2ce", "problem_8e1813be", "problem_bc1d5164", "problem_ce602527", "problem_5c2c9af4", "problem_75b8110e", "problem_941d9a10", "problem_c3f564a4", "problem_1a07d186", "problem_d687bc17", "problem_9af7a82c", "problem_6e19193c", "problem_ef135b50", "problem_cbded52d", "problem_8a004b2b", "problem_e26a3af2", "problem_6cf79266", "problem_a87f7484", "problem_4093f84a", "problem_ba26e723", "problem_4612dd53", "problem_29c11459", "problem_963e52fc", "problem_ae3edfdc", "problem_1f0c79e5", "problem_56dc2b01", "problem_e48d4e1a", "problem_6773b310", "problem_780d0b14", "problem_2204b7a8", "problem_d9f24cd1", "problem_b782dc8a", "problem_673ef223", "problem_f5b8619d", "problem_f8c80d96", "problem_ecdecbb3", "problem_e5062a87", "problem_a8d7556c", "problem_4938f0c2", "problem_834ec97d", "problem_846bdb03", "problem_90f3ed37", "problem_8403a5d5", "problem_91413438", "problem_539a4f51", "problem_5daaa586", "problem_3bdb4ada", "problem_ec883f72", "problem_2bee17df", "problem_e8dc4411", "problem_e40b9e2f", "problem_29623171", "problem_a2fd1cf0", "problem_b0c4d837", "problem_8731374e", "problem_272f95fa", "problem_db93a21d", "problem_53b68214", "problem_d6ad076f", "problem_6cdd2623", "problem_a3df8b1e", "problem_8d510a79", "problem_cdecee7f", "problem_3345333e", "problem_b190f7f5", "problem_caa06a1f", "problem_e21d9049", "problem_d89b689b", "problem_746b3537", "problem_63613498", "problem_06df4c85", "problem_f9012d9b", "problem_4522001f", "problem_a48eeaf7", "problem_eb5a1d5d", "problem_e179c5f4", "problem_228f6490", "problem_995c5fa3", "problem_d06dbe63", "problem_36fdfd69", "problem_0a938d79", "problem_045e512c", "problem_82819916", "problem_99fa7670", "problem_72322fa7", "problem_855e0971", "problem_a78176bb", "problem_952a094c", "problem_6d58a25d", "problem_6aa20dc0", "problem_e6721834", "problem_447fd412", "problem_2bcee788", "problem_776ffc46", "problem_f35d900a", "problem_0dfd9992", "problem_29ec7d0e", "problem_36d67576", "problem_98cf29f8", "problem_469497ad", "problem_39e1d7f9", "problem_484b58aa", "problem_3befdf3e", "problem_9aec4887", "problem_49d1d64f", "problem_57aa92db", "problem_aba27056", "problem_f1cefba8", "problem_1e32b0e9", "problem_28e73c20", "problem_4c5c2cf0", "problem_508bd3b6", "problem_6d0160f0", "problem_f8a8fe49", "problem_d07ae81c", "problem_6a1e5592", "problem_0e206a2e", "problem_d22278a0", "problem_4290ef0e", "problem_50846271", "problem_b527c5c6", "problem_150deff5", "problem_b7249182", "problem_9d9215db", "problem_6855a6e4", "problem_264363fd", "problem_7df24a62", "problem_f15e1fac", "problem_234bbc79", "problem_22233c11", "problem_2dd70a9a", "problem_a64e4611", "problem_7837ac64", "problem_a8c38be5", "problem_b775ac94", "problem_97a05b5b", "problem_3e980e27"]
    # tasks = tasks[1:150]

    return [
        Result(
            x.problem_name,
            x.solved,
            x.execution_time,
            x.programs_enumerated
        )
        for x in data #if x.problem_name in tasks
    ]
end

function cumulative_curve(results, field::Symbol, max, min)
    sorted = sort(results, by = r -> getfield(r, field))

    costs = [getfield(r, field) for r in sorted]
    solved = Int.(getfield.(sorted, :solved))

    cumulative_solved = cumsum(solved)

    percent_solved = cumulative_solved ./ 5

    mask = costs .> 0
    costs = costs[mask]
    percent_solved = percent_solved[mask]

    pushfirst!(costs, min)
    pushfirst!(percent_solved, percent_solved[begin])

    push!(costs, max)
    push!(percent_solved, percent_solved[end])

    return costs, percent_solved
end

function cumulative_from_costs(costs::Vector{Float64}, max, min)
    sorted = sort(costs)
    solved = collect(1:length(sorted))

    pushfirst!(sorted, min)
    pushfirst!(solved, solved[begin])

    push!(sorted, max)
    push!(solved, solved[end])

    return sorted, solved
end

function best_worst_curve(results, field::Symbol, max_x, min_x)
    best_costs, worst_costs = aggregate_best_worst(results, field)

    # best-case ordering (optimistic)
    x_best, y_best = cumulative_from_costs(best_costs, max_x, min_x)

    # worst-case ordering (pessimistic)
    x_worst, y_worst = cumulative_from_costs(worst_costs, max_x, min_x)

    return (x_best, y_best), (x_worst, y_worst)
end

function make_plots(files, field, plot_kwargs, series_kwargs)
    global_min = Inf
    global_max = -Inf
    result_sizes = []

    for file in files
        r = load_results(file)
        global_min = min(global_min, minimum(getfield.(r, field)))
        global_max = max(global_max, maximum(getfield.(r, field)))
        push!(result_sizes, length(r))
    end

    x_plot_max = maximum(first(plot_kwargs.xticks))
    x_plot_min = minimum(first(plot_kwargs.xticks))

    @show result_sizes
    !allequal(result_sizes) && @warn "Result files contain unequal amount of problems: $(result_sizes)"
    x_plot_max < global_max && @warn "Global max $global_max falls out of xticks"
    x_plot_min > global_min && @warn "Global min $global_min falls out of xticks"

    problems = occursin("bitvectors", files[1]) ? 151 : occursin("strings", files[1]) ? 67 : 400

    p = plot(;
        xlabel = field == :execution_time ? "Execution time (sec)" : "Programs evaluated",
        ylabel = "Problems solved (out of $problems)",
        xlims = (x_plot_min, x_plot_max),
        legend = :outerbottom,

        # Typography (all text sizes)
        guidefont = font(10),
        tickfont  = font(9),
        legendfont = font(9),

        grid = true,
        gridalpha = 0.25,
        gridcolor = :gray,
        plot_kwargs...,
    )

    hline!([problems], linestyle = :dash, color = :gray, label = "")
    annotate!(
        x_plot_max * 1.5,  # slightly to the right
        problems,
        text("$problems", 9)
    )

    for (i, file) in enumerate(files)
        results = load_results(file)

        x, y = cumulative_curve(results, field, x_plot_max, x_plot_min)

        plot!(
            p, 
            x, 
            y; 
            lw = 2, 
            fillrange=y,
            fillalpha=0.2,
            series_kwargs[i]...
        )

        annotate!(
            x_plot_max * 1.5,  # slightly to the right
            y[end],
            text(string(Int64(round(y[end]))), 9, series_kwargs[i].color)
        )

        (best_x, best_y), (worst_x, worst_y) = best_worst_curve(results, field, x_plot_max, x_plot_min)
        bw_x, best_y, worst_y = step_align(best_x, best_y, worst_x, worst_y)

        plot!(
            p,
            bw_x, 
            best_y,
            fillrange=worst_y,
            fillalpha=0.2,
            color=series_kwargs[i].color,
            linealpha=0.0,
            label=false,
        )

        @show series_kwargs[i].label, y[end]
    end

    display(p)
end

#=

General plot settings

=#
gr()
default(fontfamily="Computer Modern")


function strings_time_vs_acc()
    plot_kwargs = (
        xticks = (r = -2:4; ([10.0^n for n in r], ["10e$n" for n in r])),
        xscale = :log10,
        yticks = 0:10:70,
        ylims = (0, 70),
        right_margin = 10Plots.mm,
        title = "Comparing overall execution time",
    )
    series_kwargs = [
        (label = "Phalcon", color = RGB(0.00, 0.45, 0.70)),
        (label = "Phalcon transferable properties", color = RGB(0.84, 0.37, 0.00)),
        (label = "Phalcon transferable properties repeated", color = RGB(0.84, 0.37, 0.80)),
    ]
    names = [
        "phalcon_strings", 
        "transferable_phalcon_strings_test",
        "transferable_phalcon_strings_repeat",
    ]
    files = ["data/$(name).json" for name in names]
    make_plots(files, :execution_time, plot_kwargs, series_kwargs)
    savefig("plots/transferable_strings_time_vs_acc.png")
end


function strings_enum_vs_acc()
    plot_kwargs = (
        xticks = (r = 2:7; ([10.0^n for n in r], ["10e$n" for n in r])),
        xscale = :log10,
        yticks = 0:10:70,
        ylims = (0, 70),
        right_margin = 10Plots.mm,
        title = "Comparing overall program evaluations",
    )
    series_kwargs = [
        (label = "Phalcon", color = RGB(0.00, 0.45, 0.70)),
        (label = "Phalcon transferable properties", color = RGB(0.84, 0.37, 0.00)),
        (label = "Phalcon transferable properties repeated", color = RGB(0.84, 0.37, 0.80)),
    ]
    names = [
        "phalcon_strings", 
        "transferable_phalcon_strings_test",
        "transferable_phalcon_strings_repeat",
    ]
    files = ["data/$(name).json" for name in names]
    make_plots(files, :programs_enumerated, plot_kwargs, series_kwargs)
    savefig("plots/transferable_strings_enum_vs_acc.png")
end

function bitvectors_time_vs_acc()
    plot_kwargs = (
        xticks = (r = -2:4; ([10.0^n for n in r], ["10e$n" for n in r])),
        xscale = :log10,
        yticks = 0:20:160,
        ylims = (0, 160),
        right_margin = 10Plots.mm,
        title = "Comparing overall execution time",
    )
    series_kwargs = [
        (label = "Phalcon", color = RGB(0.00, 0.45, 0.70)),
        (label = "Phalcon transferable properties", color = RGB(0.84, 0.37, 0.00)),
    ]
    names = [
        "phalcon_bitvectors", 
        "transferable_phalcon_bitvectors",
    ]
    files = ["data/$(name).json" for name in names]
    make_plots(files, :execution_time, plot_kwargs, series_kwargs)
    savefig("plots/transferable_bitvectors_time_vs_acc.png")
end


function bitvectors_enum_vs_acc()
    plot_kwargs = (
        xticks = (r = 2:7; ([10.0^n for n in r], ["10e$n" for n in r])),
        xscale = :log10,
        yticks = 0:20:160,
        ylims = (0, 160),
        right_margin = 10Plots.mm,
        title = "Comparing overall program evaluations",
    )
    series_kwargs = [
        (label = "Phalcon", color = RGB(0.00, 0.45, 0.70)),
        (label = "Phalcon transferable properties", color = RGB(0.84, 0.37, 0.00)),
    ]
    names = [
        "phalcon_bitvectors", 
        "domain_phalcon_bitvectors",
    ]
    files = ["data/$(name).json" for name in names]
    make_plots(files, :programs_enumerated, plot_kwargs, series_kwargs)
    savefig("plots/transferable_bitvectors_enum_vs_acc.png")
end

function arc_time_vs_acc()
    plot_kwargs = (
        xticks = (r = -2:4; ([10.0^n for n in r], ["10e$n" for n in r])),
        xscale = :log10,
        yticks = 0:10:100,
        ylims = (0, 100),
        right_margin = 10Plots.mm,
        title = "Comparing overall execution time",
    )
    series_kwargs = [
        (label = "Phalcon", color = RGB(0.00, 0.45, 0.70)),
        (label = "Phalcon transferable properties", color = RGB(0.84, 0.37, 0.00)),
    ]
    names = [
        "phalcon_bitvectors", 
        "transferable_phalcon_bitvectors",
    ]
    files = ["data/$(name).json" for name in names]
    make_plots(files, :execution_time, plot_kwargs, series_kwargs)
    savefig("plots/transferable_arc_time_vs_acc.png")
end


function arc_enum_vs_acc()
    plot_kwargs = (
        xticks = (r = 2:7; ([10.0^n for n in r], ["10e$n" for n in r])),
        xscale = :log10,
        yticks = 0:10:100,
        ylims = (0, 100),
        right_margin = 10Plots.mm,
        title = "Comparing overall program evaluations",
    )
    series_kwargs = [
        (label = "Phalcon", color = RGB(0.00, 0.45, 0.70)),
        (label = "Phalcon transferable properties", color = RGB(0.84, 0.37, 0.00)),
    ]
    names = [
        "phalcon_arc", 
        "transferable_phalcon_arc",
    ]
    files = ["data/$(name).json" for name in names]
    make_plots(files, :programs_enumerated, plot_kwargs, series_kwargs)
    savefig("plots/transferable_arc_enum_vs_acc.png")
end

# strings_time_vs_acc()
# strings_enum_vs_acc()
bitvectors_time_vs_acc()
bitvectors_enum_vs_acc()
# arc_time_vs_acc()
# arc_enum_vs_acc()