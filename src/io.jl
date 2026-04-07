const PROGRESS_INDICATOR_DT_SECOND = 5
const DOWNLOAD_TO_TMP_ENV_VAR = "WORMWIDEWEBDATA_DOWNLOAD_VIA_TMP"

function _env_var_is_true(name::AbstractString)
    value = lowercase(strip(get(ENV, name, "")))
    return value in ("1", "true", "t", "yes", "y", "on")
end

"""
    save_dict_to_h5(path_h5, dict; metadata=nothing)

Write `dict` to an HDF5 file under the `"data"` group. If `metadata` is
provided, it is written under the `"metadata"` group.
"""
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

"""
    _write_dict(h5group, dict)

Internal recursive writer used by `save_dict_to_h5` to serialize nested `Dict`
values into HDF5 groups and datasets.
"""
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

"""
    load_dict_from_h5(path_h5)

Load and return the `"data"` group from an HDF5 file as a dictionary-like
structure.
"""
function load_dict_from_h5(path_h5::AbstractString)
    h5open(path_h5, "r") do file
        return (data = read(file, "data"), metadata = read(file, "metadata"))
    end
end

function _get_stored_checksum(metadata::Dict)
    for (k, v) in metadata
        if startswith(k, "blake") || startswith(k, "sha256")
            return k, v
        end
    end
    error("no blake3 or sha256 checksum found in the metadata dictionary")
end

"""
    load_dict_from_json(path_json)

Parse a JSON file and return the value stored in its top-level `"data"` field.
"""
function load_dict_from_json(path_json::AbstractString)
    json = JSON.parsefile(path_json, dicttype = Dict)
    return (data = json["data"], metadata = json["metadata"])
end

"""
    save_dict_to_json(path_json, dict; metadata=nothing, allow_nan=true)

Write `dict` to JSON using the schema `{"data": ..., "metadata": ...}`.
When `allow_nan=false`, JSON encoding fails on NaN and Inf values.
"""
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

"""
    save_dict_to_h5_json(path_dir, file_basename, dict; metadata=nothing, allow_nan=true)

Save `dict` to both HDF5 and JSON using the same basename in `path_dir`.
Files are written as `<file_basename>.h5` and `<file_basename>.json`.
"""
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
        allow_nan = allow_nan,
    )

    nothing
end

"""
    download_file(url_download, path_save; checksum=nothing, f_checksum=md5sum, verbose=true, headers=Pair{String,String}[])

Download a file to `path_save`. If `checksum` is provided, verify it with
`f_checksum` and throw an error on mismatch. Existing files are reused when
the checksum already matches. If `ENV["WORMWIDEWEBDATA_DOWNLOAD_VIA_TMP"]`
is set to a truthy value (`"1"`, `"true"`, `"yes"`, ...), download to `/tmp`
first and then move the file to `path_save`.
"""
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

    use_tmp_staging = _env_var_is_true(DOWNLOAD_TO_TMP_ENV_VAR)
    path_download = use_tmp_staging ? tempname("/tmp") : path_save

    try
        if verbose
            p = Progress(
                100;
                dt = PROGRESS_INDICATOR_DT_SECOND,
                desc = "Downloading: ",
                barglyphs = BarGlyphs("[=> ]"),
            )

            function _progress(total, downloaded)
                if total > 0
                    percentage = Int(round(100 * downloaded / total))
                    update!(p, min(percentage, 99))
                end
            end

            Downloads.download(url_download, path_download, progress = _progress, headers = headers)
            update!(p, 100)
            finish!(p)
        else
            Downloads.download(url_download, path_download, headers = headers)
        end

        if !isnothing(checksum) && f_checksum(path_download) != checksum
            error("file downloaded but checksum is incorrect")
        end

        if use_tmp_staging
            mv(path_download, path_save; force = true)
        end
    finally
        if use_tmp_staging && ispath(path_download)
            rm(path_download; force = true, recursive = true)
        end
    end

    return
end


"""
    unarchive(path_archive, path_target=nothing, verbose=false)

Extract supported archives (`.tar.bz2` and `.bz2`). For `.tar.bz2`, extraction
can be redirected to `path_target`.
"""
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

"""
    sha256(path_file)

Return the SHA-256 checksum of `path_file` as a lowercase hex string.
"""
function sha256(path_file::AbstractString)
    cmd =
        !isnothing(Sys.which("shasum")) ? `shasum -a 256 $(path_file)` :
        !isnothing(Sys.which("sha256sum")) ? `sha256sum $(path_file)` : nothing

    isnothing(cmd) && error("missing checksum tool: install `shasum` or `sha256sum`")
    return split(read(cmd, String))[1]
end

"""
    blake3(path_file)

Return the BLAKE3 checksum of `path_file` as a lowercase hex string.
Requires `b3sum` to be available in `PATH`.
"""
function blake3(path_file::AbstractString)
    isnothing(Sys.which("b3sum")) && error("missing checksum tool: install `b3sum`")
    return split(read(`b3sum $(path_file)`, String))[1]
end

"""
    md5sum(path_file)

Return the MD5 checksum of `path_file` as a lowercase hex string.
"""
function md5sum(path_file::AbstractString)
    cmd =
        !isnothing(Sys.which("md5sum")) ? `md5sum $(path_file)` :
        !isnothing(Sys.which("md5")) ? `md5 -q $(path_file)` : nothing

    isnothing(cmd) && error("missing checksum tool: install `md5sum` or `md5`")
    return split(read(cmd, String))[1]
end
