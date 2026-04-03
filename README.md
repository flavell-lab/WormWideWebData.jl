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

## Generated JSON files
### metadata
Each file should contain a metadata entry:
```
  "checksum_h5"                       => "99b5975ddea434e5e03510ac380d89ac8d7d4…
  "blake3_relative_encoding_strength" => "c28384748008c66b4178cc3afaa909263f4d4…
  "blake3_neuropal_dict"              => "88d19fddf57f3469fa4bd4cf917742d26e6c8…
  "blake3_analysis_dict"              => "b6e66580cfae784a81e5a9fcc757eaeec88e6…
  "blake3_fit_results"                => "1c4bf00c535d814e851a03170542fc3008295…
  "source_filename"                   => "2021-08-17-01-data.h5"
  "paper_id"                          => "atanas_kim_2023"
  ```
  - blake3_relative_encoding_strength: blake3 checksum of the relative_encoding_strength.jld2
  - blake3_neuropal_dict: blake3 checksum of the neuropal dictionary file used
  - blake3_analysis_dict: blake3 checksum of the analysis_dict.jld2
  - blake3_fit_results: blake3 checksum of the fit_results.jld2
  - source_filename: filename of the raw neural/behavioral h5 file used
  - checksum_h5: sha256 checksum of the h5 source file
  - paper_id: paper id

checksum_h5 should match the checksum found on https://github.com/flavell-lab/WormWideWeb-data/tree/main/activity/raw

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
