"""
    get_zenodo_metadata(record_id=nothing; request_url=nothing, fetch_latest=true)

Fetch Zenodo record metadata by `record_id` or direct API URL. When
`fetch_latest=true`, follows the record's `links.latest` endpoint once.
"""
function get_zenodo_metadata(
    record_id::Union{AbstractString,Nothing} = nothing;
    request_url::Union{AbstractString,Nothing} = nothing,
    fetch_latest::Bool = true,
)
    # 1. input argument
    if isnothing(record_id) && isnothing(request_url)
        error("You must provide either a record_id or a request_url.")
    end
    if !isnothing(record_id) && !isnothing(request_url)
        error("Both record_id and request_url were provided; please provide only one.")
    end

    # 2. URL
    api_url =
        isnothing(record_id) ? request_url : "https://zenodo.org/api/records/$record_id"

    # 3. fetch
    response = HTTP.get(api_url)
    data = JSON.parse(String(response.body), dicttype = Dict{String,Any})

    # 4. Handle recursion for latest version
    if fetch_latest && haskey(data, "links") && haskey(data["links"], "latest")
        latest_url = data["links"]["latest"]

        # Check if we are already at the latest to avoid infinite loops
        if latest_url != api_url
            @info "Redirecting to latest version..."
            return get_zenodo_metadata(
                nothing;
                request_url = latest_url,
                fetch_latest = false,
            )
        end
    end

    return data
end

"""
    _select_zenodo_file_record(records, filename)

Internal helper that selects a file record whose `key` matches `filename`.
"""
function _select_zenodo_file_record(records::Vector, filename::AbstractString)
    for record in records
        if record["key"] == filename
            return record
        end
    end

    error("file $filename not found in the given records")
end

"""
    get_zenodo_file(file_records, filename, path_dir_target, path_dir_unarchive=nothing; verbose=true)

Download one file from Zenodo metadata records, verify checksum, and optionally
unarchive `.bz2` outputs.
"""
function get_zenodo_file(
    file_records::Vector,
    filename::AbstractString,
    path_dir_target::AbstractString,
    path_dir_unarchive::Union{AbstractString,Nothing} = nothing;
    verbose::Bool = true,
)
    file_record = _select_zenodo_file_record(file_records, filename)

    mkpath(path_dir_target)
    path_save = joinpath(path_dir_target, filename)

    url_download = file_record["links"]["self"]
    download_file(
        url_download,
        path_save,
        checksum = split(file_record["checksum"], ':')[2],
        verbose = verbose,
    )

    if endswith(path_save, ".bz2")
        unarchive(path_save, path_dir_unarchive)
    end
end

"""
    prepare_files_zenodo(record_id, path_dir_target; neuropal_label=false, encoding_data=false, verbose=true)

Download the required file bundle for a Zenodo-backed paper into
`path_dir_target`.
"""
function prepare_files_zenodo(
    record_id::AbstractString,
    path_dir_target::AbstractString;
    neuropal_label::Bool = false,
    encoding_data::Bool = false,
    verbose::Bool = true,
)
    zenodo_record = get_zenodo_metadata(record_id, fetch_latest = true)
    file_records = zenodo_record["files"]

    manifest = generate_download_manifest(
        path_dir_target,
        encoding_data = encoding_data,
        neuropal_label = neuropal_label,
    )

    for (fname, path_dir_target_unarchive) in manifest
        @info "processing $fname ..."
        get_zenodo_file(
            file_records,
            fname,
            path_dir_target,
            path_dir_target_unarchive,
            verbose = verbose,
        )
    end

    nothing
end
