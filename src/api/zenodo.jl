function get_zenodo_metadata(
    record_id::Union{AbstractString, Nothing} = nothing;
    request_url::Union{AbstractString, Nothing} = nothing,
    fetch_latest::Bool = true
)
    # 1. input argument
    if isnothing(record_id) && isnothing(request_url)
        error("You must provide either a record_id or a request_url.")
    end
    if !isnothing(record_id) && !isnothing(request_url)
        error("Both record_id and request_url were provided; please provide only one.")
    end

    # 2. URL
    api_url = isnothing(record_id) ? request_url : "https://zenodo.org/api/records/$record_id"

    # 3. fetch
    response = HTTP.get(api_url)
    data = JSON.parse(String(response.body), dicttype=Dict{String, Any})
    
    # 4. Handle recursion for latest version
    if fetch_latest && haskey(data, "links") && haskey(data["links"], "latest")
        latest_url = data["links"]["latest"]
        
        # Check if we are already at the latest to avoid infinite loops
        if latest_url != api_url
            @info "Redirecting to latest version..."
            return get_zenodo_metadata(nothing; request_url=latest_url, fetch_latest=false)
        end
    end

    return data
end