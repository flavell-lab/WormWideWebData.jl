
function save_dict_to_h5(path_h5::AbstractString, dict::Dict; metadata = nothing)
    h5open(path_h5, "w") do file
        data = create_group(file, "data")
        _write_dict(data, dict)

        if !isnothing(metadata)
            meta = create_group(file, "metadata")
            _write_dict(meta, metadata)
        end
    end
end

function _write_dict(h5group, dict::Dict)
    for (k, v) in dict
        key = string(k)

        if v isa Dict
            # 1. create the group and capture the handle
            subgroup = create_group(h5group, key)

            try
                # 2. recurse into the new group
                _write_dict(subgroup, v)
            finally
                # 3. close group
                close(subgroup)
            end
        else
            h5group[key] = v
        end
    end
end

function load_dict_from_h5(path_h5::AbstractString)
    h5open(path_h5, "r") do file
        return read(file, "data")
    end
end

function save_dict_to_h5_json(
    path_dir::AbstractString,
    file_basename::AbstractString,
    dict::Dict;
    metadata = nothing,
    allow_nan = true,
)
    # h5
    save_dict_to_h5(joinpath(path_dir, file_basename * ".h5"), dict, metadata = metadata)

    # json
    dict_save = Dict("data"=>dict)
    if !isnothing(metadata)
        dict_save["metadata"] = metadata
    end
    open(joinpath(path_dir_target, file_basename * ".json"), "w") do f
        write(f, JSON.json(dict_save, pretty = 4, allownan = allow_nan))
    end

    nothing
end

sha256(path_file::AbstractString) = split(read(`shasum -a 256 $(path_file)`, String))[1]

blake3(path_file::AbstractString) = split(read(`b3sum $(path_file)`, String))[1]
