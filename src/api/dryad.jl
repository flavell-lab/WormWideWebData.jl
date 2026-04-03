"""
    get_dryad_token(client_id, client_secret)

Request an OAuth access token from Dryad using client credentials.
"""
function get_dryad_token(client_id::AbstractString, client_secret::AbstractString)
    url = "https://datadryad.org/oauth/token"
    body = Dict(
        "grant_type" => "client_credentials",
        "client_id" => client_id,
        "client_secret" => client_secret,
    )
    resp = HTTP.post(url, ["Content-Type" => "application/json"], JSON.json(body))
    response = JSON.parse(String(resp.body))

    return response["access_token"]
end

"""
    get_dryad_files_metadata(doi)

Resolve a Dryad DOI to its latest dataset version and return the associated
file metadata list.
"""
function get_dryad_files_metadata(doi::AbstractString)
    # 1. normalize and Encode DOI
    clean_doi = startswith(doi, "doi:") ? doi : "doi:$doi"
    encoded_doi = escapeuri(clean_doi)

    base_url = "https://datadryad.org/api/v2"
    dataset_url = "$base_url/datasets/$encoded_doi"

    try
        # 2. fetch
        response = HTTP.get(dataset_url)
        dataset_data = JSON.parse(String(response.body))

        # 3. latest version
        links = dataset_data["_links"]
        version_path = links["stash:version"]["href"]
        version_url = "https://datadryad.org$version_path"

        # fetch version details
        version_resp = HTTP.get(version_url)
        version_data = JSON.parse(String(version_resp.body))

        # 4. fetch and list files
        files_path = version_data["_links"]["stash:files"]["href"]
        files_url = "https://datadryad.org$files_path"

        files_resp = HTTP.get(files_url)
        files_data = JSON.parse(String(files_resp.body))

        files_list = files_data["_embedded"]["stash:files"]

        return files_list
    catch e
        @error "An error occurred while fetching the Dryad dataset." exception=e
    end
end

"""
    _select_dryad_file_record(records, filename)

Internal helper that selects a Dryad file record whose `path` matches
`filename`.
"""
function _select_dryad_file_record(records::Vector, filename::AbstractString)
    for record in records
        if record["path"] == filename
            return record
        end
    end

    error("file $filename not found in the given records")
end

"""
    get_dryad_file(file_records, filename, path_dir_target, path_dir_unarchive=nothing; verbose=true, token)

Download one file from Dryad metadata records using bearer-token authentication,
verify checksum, and optionally unarchive `.bz2` outputs.
"""
function get_dryad_file(
    file_records::Vector,
    filename::AbstractString,
    path_dir_target::AbstractString,
    path_dir_unarchive::Union{AbstractString,Nothing} = nothing;
    verbose::Bool = true,
    token::AbstractString,
)

    file_record = _select_dryad_file_record(file_records, filename)

    url_download =
        "https://datadryad.org" * file_record["_links"]["self"]["href"] * "/download"
    headers = ["Authorization" => "Bearer $token"]
    @assert filename == file_record["path"]

    path_save = joinpath(path_dir_target, filename)

    @assert file_record["digestType"] == "sha-256" "dryad checksum function has been changed. expected: sha-256. given: $(file_record["digestType"])"

    download_file(
        url_download,
        path_save,
        checksum = file_record["digest"],
        f_checksum = sha256,
        verbose = verbose,
        headers = headers,
    )

    if endswith(path_save, ".bz2")
        unarchive(path_save, path_dir_unarchive)
    end
end

"""
    prepare_files_dryad(doi, path_dir_target; token, neuropal_label=false, encoding_data=false, verbose=true)

Download the required file bundle for a Dryad-backed paper into
`path_dir_target`.
"""
function prepare_files_dryad(
    doi::AbstractString,
    path_dir_target::AbstractString;
    token::AbstractString,
    neuropal_label::Bool = false,
    encoding_data::Bool = false,
    verbose::Bool = true,
)
    file_records = get_dryad_files_metadata(doi)

    manifest = [("processed_h5.tar.bz2", joinpath(path_dir_target, "datasets")),]

    if encoding_data
        manifest = vcat(
            manifest,
            [
                ("neuron_categorization.h5.bz2", nothing),
                ("encoding_changes_corrected.h5.bz2", nothing),
                ("relative_encoding_strength_median.h5.bz2", nothing),
                ("tuning_strength.h5.bz2", nothing),
                ("sampled_tau_vals_median.h5.bz2", nothing),
                ("fit_ranges.h5.bz2", nothing),
            ],
        )
    end
    neuropal_label && push!(manifest, ("neuropal_label.json.bz2", nothing))

    for (fname, path_dir_target_unarchive) in manifest
        @info "processing $fname ..."
        get_dryad_file(
            file_records,
            fname,
            path_dir_target,
            path_dir_target_unarchive,
            verbose = verbose,
            token = token,
        )
    end

    nothing
end
