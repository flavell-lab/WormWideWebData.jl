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

function load_dict_from_json(path_json::AbstractString)
    JSON.parsefile(path_json, dicttype = Dict)["data"]
end

function save_dict_to_json(
    path_json::AbstractString,
    dict::Dict;
    metadata = nothing,
    allow_nan = true,
)
    dict_save = Dict{String,Any}("data"=>dict)
    if !isnothing(metadata)
        dict_save["metadata"] = metadata
    end
    open(path_json, "w") do f
        write(f, JSON.json(dict_save, pretty = 4, allownan = allow_nan))
    end

    nothing
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
    save_dict_to_json(
        joinpath(path_dir, file_basename * ".json"),
        dict,
        metadata = metadata,
    )

    nothing
end

function download_file(
    url_download::AbstractString,
    path_save::AbstractString;
    checksum::Union{AbstractString,Nothing} = nothing,
    f_checksum::Function = md5sum,
    verbose::Bool = true,
    headers::AbstractVector = Pair{String,String}[],
)
    # file exists, check the checksum
    if !isnothing(checksum) && isfile(path_save) && f_checksum(path_save) == checksum
        # no need to download again
        verbose && @info "exisiting file matches the given checksum: $(basename(path_save))"
        return
    end

    if verbose
        p = Progress(100; dt = 0.2, desc = "Downloading: ", barglyphs = BarGlyphs("[=> ]"))

        function _progress(total, downloaded)
            if total > 0
                percentage = Int(round(100 * downloaded / total))
                update!(p, min(percentage, 99))
            end
        end

        Downloads.download(url_download, path_save, progress = _progress, headers = headers)
        update!(p, 100)
        finish!(p)
    else
        Downloads.download(url_download, path_save)
    end

    if !isnothing(checksum) && f_checksum(path_save) == checksum
        return
    else
        error("file downloaded but checksum is incorrect")
    end
end


function unarchive(
    path_archive::AbstractString,
    path_target::Union{AbstractString,Nothing} = nothing,
    verbose::Bool = false,
)
    verbose && @info "unarchiving $path_archive"
    if endswith(path_archive, ".tar.bz2")
        if isnothing(path_target)
            run(`tar -xjf $path_archive`)
        else
            mkpath(path_target)
            run(`tar -xjf $path_archive -C $path_target`)
        end
    elseif endswith(path_archive, ".bz2")
        run(`bunzip2 -kf $path_archive`)
    else
        error("unsupported archive type")
    end

    nothing
end

sha256(path_file::AbstractString) = split(read(`shasum -a 256 $(path_file)`, String))[1]

blake3(path_file::AbstractString) = split(read(`b3sum $(path_file)`, String))[1]

md5sum(path_file::AbstractString) = split(read(`md5sum $(path_file)`, String))[1]
