"""
    package_h5_datasets(path_dir, archive_name="processed_h5.tar.bz2"; verbose=false)

Validate the `.h5` files in `path_dir`, write `h5_sha256.csv`, and package the
HDF5 files plus that checksum manifest into a flat `tar.bz2` archive compressed
with `pbzip2`. Relative `archive_name` values are saved under `path_dir`.
"""
function package_h5_datasets(
    path_dir::AbstractString,
    archive_name::AbstractString = "processed_h5.tar.bz2";
    verbose::Bool = false,
)
    check_h5_datasets_for_paper_json(path_dir; verbose = verbose)

    path_dir_abs = abspath(path_dir)
    archive_path = isabspath(archive_name) ? archive_name : joinpath(path_dir_abs, archive_name)
    archive_path = abspath(archive_path)
    mkpath(dirname(archive_path))

    isnothing(Sys.which("tar")) && error("missing archive tool: install `tar`")
    isnothing(Sys.which("pbzip2")) && error("missing compression tool: install `pbzip2`")

    checksum_name = "h5_sha256.csv"
    path_checksum = joinpath(path_dir_abs, checksum_name)
    write_file_checksums_to_csv(
        path_dir_abs,
        path_checksum;
        ext = ".h5",
        f_checksum = WormWideWebData.sha256,
        header = true,
    )

    members = vcat(_h5_dataset_filenames(path_dir_abs), [checksum_name])
    verbose && @info "Packaging $(length(members) - 1) HDF5 files into $archive_path"

    member_args = join(Base.shell_escape.(members), " ")
    cmd =
        "tar -cf - -- " *
        member_args *
        " | pbzip2 -c > " *
        Base.shell_escape(archive_path)
    cd(path_dir_abs) do
        run(`sh -c $cmd`)
    end

    return archive_path
end
