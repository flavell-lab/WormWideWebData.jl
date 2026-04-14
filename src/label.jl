"""
    generate_neuropal_json(path_dir_target, path_neuropal_dict, verbose=true; json_name="neuropal_label.json", key_dataset="dict_neuropal_label", key_sub=nothing, overwrite=false, compress=true)

Convert a Neuropal label dictionary stored in JLD2 into a normalized JSON file
with checksum metadata. By default, also write a bzip2-compressed copy at
`<json_name>.bz2`.
"""
function generate_neuropal_json(
    path_dir_target::AbstractString,
    path_neuropal_dict::AbstractString,
    verbose::Bool = true;
    json_name::AbstractString = "neuropal_label.json",
    key_dataset::AbstractString = "dict_neuropal_label",
    key_sub::Union{AbstractString,Nothing} = nothing,
    overwrite::Bool = false,
    compress::Bool = true,
)
    path_save = joinpath(path_dir_target, json_name)
    path_save_bz2 = path_save * ".bz2"
    if isfile(path_save) && !overwrite
        error("File already exists at $path_save")
    end
    if compress && isfile(path_save_bz2) && !overwrite
        error("File already exists at $path_save_bz2")
    end
    if compress && isnothing(Sys.which("pbzip2"))
        error("missing compression tool: install `pbzip2`")
    end

    blake_neuropal_dict = blake3(path_neuropal_dict)
    dict_neuropal_label =
        isnothing(key_sub) ? load(path_neuropal_dict, key_dataset) :
        load(path_neuropal_dict, key_dataset)[key_sub]

    neuropal_label_compiled = Dict()
    for (uid, d) in dict_neuropal_label
        neuropal_label_compiled[uid] = Dict("idx_neuron-label"=>d[1])
    end

    save_dict_to_json(
        path_save,
        neuropal_label_compiled,
        metadata = Dict("blake3_neuropal_dict"=>blake_neuropal_dict),
    )

    verbose && @info "neuropal dict saving complete: $path_save"
    if compress
        run(`pbzip2 -kf $path_save`)
        verbose && @info "neuropal dict compression complete: $path_save_bz2"
    end

    return path_save
end

function check_labels(dict_label::Dict)
    output_dict = Dict{String,Dict}()
    for (idx_neuron_str, label_data) in dict_label
        if label_data isa Dict
            output_dict[idx_neuron_str] = label_data
        elseif label_data isa Vector
            # check for multiple labels
            n_label_data = length(label_data)
            if n_label_data == 0
                # skip, no data
            elseif n_label_data == 1
                # use the single label
                output_dict[idx_neuron_str] = label_data[1]
            else
                # multiple label, pick the highest confidence one
                output_dict[idx_neuron_str] = pop!(label_data)
                while length(label_data) > 0
                    candidate_ = pop!(label_data)
                    if candidate_["confidence"] > output_dict[idx_neuron_str]["confidence"]
                        output_dict[idx_neuron_str] = candidate_
                    end
                end
            end
        end
    end

    return output_dict
end
