using JSON3
using HerbBenchmarks


bustle_tasks = [
    "problem_bikes",
    "problem_dr_name",
    "problem_firstname",
    "problem_initials",
    "problem_lastname",

    "problem_name_combine_2",
    "problem_name_combine_3",
    "problem_name_combine_4",
    "problem_name_combine",
    "problem_phone_1",

    "problem_phone_10",
    "problem_phone_2",
    "problem_phone_3",
    "problem_phone_4",
    "problem_phone_5",

    "problem_phone_6",
    "problem_phone_7",
    "problem_phone_8",
    "problem_phone_9",
    "problem_phone",
    
    "problem_reverse_name",
    "problem_univ_1",
    "problem_univ_2",
    "problem_univ_3",
    "problem_univ_4",

    "problem_univ_5",
    "problem_univ_6",
    "problem_11604909",
    "problem_17212077",
    "problem_2171308",

    "problem_25239569",
    "problem_28627624_1",
    "problem_30732554",
    "problem_31753108",
    "problem_33619752",

    "problem_34801680",
    "problem_35016216",
    "problem_35744094",
    "problem_36462127",
    "problem_37534494",

    "problem_38664547",
    "problem_38871714",
    "problem_39060015",
    "problem_41503046",
    "problem_43120683",
    
    "problem_43606446",
    "problem_add_a_line_break_with_a_formula",
    "problem_change_negative_numbers_to_positive",
    "problem_clean_and_reformat_telephone_numbers",
    "problem_create_email_address_from_name",

    "problem_create_email_address_with_name_and_domain",
    "problem_exceljet1",
    "problem_exceljet2",
    "problem_exceljet3",
    "problem_exceljet4",

    "problem_extract_word_containing_specific_text",
    "problem_extract_word_that_begins_with_specific_character",
    "problem_get_domain_from_email_address_2",
    "problem_get_domain_name_from_url",
    "problem_get_first_name_from_name",

    "problem_get_first_word",
    "problem_get_last_line_in_cell",
    "problem_get_last_name_from_name_with_comma",
    "problem_get_last_name_from_name",
    "problem_get_last_word",

    "problem_get_middle_name_from_full_name",
    "problem_join_cells_with_comma",
    "problem_join_first_and_last_name",
    "problem_most_frequently_occurring_text",
    "problem_remove_file_extension_from_filename",

    "problem_remove_leading_and_trailing_spaces_from_text",
    "problem_remove_text_by_matching",
    "problem_remove_text_by_position",
    "problem_remove_unwanted_characters",
    "problem_replace_one_character_with_another",

    "problem_stackoverflow1",
    "problem_stackoverflow10",
    "problem_stackoverflow11",
    "problem_stackoverflow2",
    "problem_stackoverflow3",

    "problem_stackoverflow4",
    "problem_stackoverflow5",
    "problem_stackoverflow6",
    "problem_stackoverflow7",
    "problem_stackoverflow8",

    "problem_stackoverflow9",
    "problem_strip_html_from_text_or_numbers",
    "problem_strip_non_numeric_characters",
    "problem_strip_numeric_characters_from_cell",
]

# load data
data = JSON3.read(read("data/phalcon_strings.json", String), Vector{Any})

# filter entries
filtered = filter(x -> x["problem_name"] in bustle_tasks, data)

path = "data/bustle_and_crossbeam/phalcon_strings_bustle.json"

# write back to file
open(path, "w") do io
    JSON3.pretty(io, filtered)
end
