function generate_neuropal_json(
    path_dir_target::AbstractString,
    path_neuropal_dict::AbstractString,
    verbose::Bool = true;
    key_dataset::AbstractString = "dict_neuropal_label",
    key_sub::Union{AbstractString,Nothing} = nothing,
)
    blake_neuropal_dict = blake3(path_neuropal_dict)
    dict_neuropal_label =
        isnothing(key_sub) ? load(path_neuropal_dict, key_dataset) :
        load(path_neuropal_dict, key_dataset)[key_sub]

    neuropal_label_compiled = Dict()
    for (uid, d) in dict_neuropal_label
        neuropal_label_compiled[uid] = Dict("roi_to_neuron"=>d[1], "neuron_to_roi"=>d[2])
    end

    save_dict_to_json(
        joinpath(path_dir_target, "neuropal_label.json"),
        neuropal_label_compiled,
        metadata = Dict("blake_neuropal_dict"=>blake_neuropal_dict),
    )

    verbose && @info "neuropal dict saving complete"
end
