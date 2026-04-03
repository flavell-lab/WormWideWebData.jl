REFERENCE_REPO_URL = "git@github.com:flavell-lab/WormWideWeb-data.git"
REFERENCE_ACTIVITY_PATH = "activity"
REFERENCE_SCRATCH_DIR = get_scratch!("wormwideweb-data")

"""
    sync_repo_sparse(repo_url, target_subdir, workspace)

Clone or update a sparse checkout of `repo_url` into `workspace`, restricted to
`target_subdir`. Returns the local path to the synced subdirectory.
"""
function sync_repo_sparse(repo_url, target_subdir, workspace)
    buffer_out = IOBuffer()
    buffer_err = IOBuffer()
    try
        cd(workspace) do
            if !isdir(joinpath(workspace, ".git"))
                run(
                    pipeline(
                        `git clone --filter=blob:none --sparse $repo_url .`,
                        stdout = buffer_out,
                        stderr = buffer_err,
                    ),
                )
                run(
                    pipeline(
                        `git sparse-checkout set $target_subdir`,
                        stdout = buffer_out,
                        stderr = buffer_err,
                    ),
                )
            else
                run(
                    pipeline(
                        `git pull origin main`,
                        stdout = buffer_out,
                        stderr = buffer_err,
                    ),
                )
            end
        end
    catch e
        println("Error syncing flavell-lab/WormWideWeb-data.git")
        println("STDOUT: ", String(take!(buffer_out)))
        println("STDERR: ", String(take!(buffer_err)))
        rethrow(e)
    end

    return joinpath(workspace, target_subdir)
end

"""
    check_dataset_type(papers, dataset_types)

Assert that each dataset type listed in `papers` exists in the allowed type
definitions from `dataset_types`.
"""
function check_dataset_type(papers, dataset_types)
    for paper_id in keys(papers)
        @assert haskey(dataset_types, paper_id) "Entry for paper \"$paper_id\" is missing in dataset_types (initial_data_activity_dataset_types.json)"
    end

    # check each dataset
    for (paper_id, datasets) in papers
        available_types = vcat(
            [dataset_type["id"] for dataset_type in dataset_types[paper_id]],
            [dataset_type["id"] for dataset_type in dataset_types["common"]],
        )
        for dataset in datasets
            uid = dataset["uid"]
            list_type = split(dataset["type"], ',')
            for type_ in list_type
                @assert type_ in available_types "$paper_id|$uid: dataset type \"$type_\" does not exist in dataset_types (initial_data_activity_dataset_types.json)"
            end
        end
    end
end

"""
    get_activity_info(repo_url=REFERENCE_REPO_URL, repo_activity_path=REFERENCE_ACTIVITY_PATH, scratch_dir=REFERENCE_SCRATCH_DIR)

Load paper metadata, dataset rows, and dataset-type definitions from the
reference activity repository. Returns `(papers_data, datasets_data, dataset_types)`.
"""
function get_activity_info(
    repo_url::AbstractString = REFERENCE_REPO_URL,
    repo_activity_path::AbstractString = REFERENCE_ACTIVITY_PATH,
    scratch_dir::AbstractString = REFERENCE_SCRATCH_DIR,
)
    path_dir_activity = sync_repo_sparse(repo_url, repo_activity_path, scratch_dir)
    path_json_paper = joinpath(path_dir_activity, "initial_data_activity_papers.json")
    path_json_type = joinpath(path_dir_activity, "initial_data_activity_dataset_types.json")

    # get paper_id list
    papers_data = JSON.parsefile(path_json_paper, dicttype = Dict)
    list_paper_id = [paper["paper_id"] for paper in papers_data]

    # paper data
    datasets_data = Dict{String,Any}()
    for paper_id in list_paper_id
        path_paper_csv = joinpath(path_dir_activity, "raw", paper_id * ".csv")
        @assert isfile(path_paper_csv) "Missing $(paper_id).csv in WormWideWeb-data/activity/raw/"

        file_paper_csv = CSV.File(path_paper_csv, stringtype = String)
        datasets_data[paper_id] =
            [Dict(string(k) => v for (k, v) in pairs(row)) for row in file_paper_csv]
    end

    # get dataset types and check for consistency
    dataset_types = JSON.parsefile(path_json_type, dicttype = Dict)
    check_dataset_type(datasets_data, dataset_types)

    return papers_data, datasets_data, dataset_types
end
