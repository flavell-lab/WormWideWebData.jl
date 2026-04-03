"""
    generate_neuropal_json(path_dir_target, path_neuropal_dict, verbose=true; json_name="neuropal_label.json", key_dataset="dict_neuropal_label", key_sub=nothing, overwrite=false)

Convert a Neuropal label dictionary stored in JLD2 into a normalized JSON file
with checksum metadata.
"""
function generate_neuropal_json(
    path_dir_target::AbstractString,
    path_neuropal_dict::AbstractString,
    verbose::Bool = true;
    json_name::AbstractString = "neuropal_label.json",
    key_dataset::AbstractString = "dict_neuropal_label",
    key_sub::Union{AbstractString,Nothing} = nothing,
    overwrite::Bool = false,
)
    path_save = joinpath(path_dir_target, json_name)
    if isfile(path_save) && !overwrite
        error("File already exists at $path_save")
    end

    blake_neuropal_dict = blake3(path_neuropal_dict)
    dict_neuropal_label =
        isnothing(key_sub) ? load(path_neuropal_dict, key_dataset) :
        load(path_neuropal_dict, key_dataset)[key_sub]

    neuropal_label_compiled = Dict()
    for (uid, d) in dict_neuropal_label
        neuropal_label_compiled[uid] = Dict("roi_to_neuron"=>d[1], "neuron_to_roi"=>d[2])
    end

    save_dict_to_json(
        path_save,
        neuropal_label_compiled,
        metadata = Dict("blake_neuropal_dict"=>blake_neuropal_dict),
    )

    verbose && @info "neuropal dict saving complete: $path_save"

    return path_save
end
