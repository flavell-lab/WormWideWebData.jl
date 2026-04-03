# WormWideWebData.jl

`WormWideWebData.jl` provides tools to:

- sync paper metadata from the WormWideWeb reference repository,
- download dataset bundles from Zenodo/Dryad,
- validate HDF5 dataset integrity,
- transform source files into normalized JSON/HDF5 outputs.

## Installation

From Julia:

```julia
using Pkg
Pkg.develop(path=".")
```

Or add from a remote git URL if this repository is hosted.

## Quick Start
### Generating encoding and neuropal files
See below to generate encoding data files (derived from analysis_dict.jld2, fit_results.jld2, etc.) for data generation.
```julia
using WormWideWebData
path_dir_target = "/kfc_encoding_h5/"
path_analysis_dict = ".../analysis_dict.jld2"
path_fit_results = ".../fit_results.jld2"
path_relative_encoding_strength = ".../relative_encoding_strength.jld2"
path_neuropal = ".../dict_neuropal_label.jld2"

generate_neuropal_json(path_dir_target, path_neuropal)

generate_encoding_files(
    path_dir_target,
    path_analysis_dict,
    path_fit_results,
    path_relative_encoding_strength
)
```
### Generating JSON files for the website
```julia
generate_all_paper_json(
    "/www-data/data/",
    "/www-data/"
)
```

## Running Tests

```bash
julia --project -e 'using Pkg; Pkg.test()'
```

Coverage run:

```bash
julia --project -e 'using Pkg; Pkg.test(coverage=true)'
```

## System Dependencies

Some workflows rely on external command-line tools:

- `git` (reference repository sync),
- `tar` and `bunzip2` (archive extraction),
- `shasum` and `md5sum` (checksums),
- `b3sum` (BLAKE3 checksum for some preprocessing paths).

Install these tools and ensure they are available in `PATH` for full functionality.
