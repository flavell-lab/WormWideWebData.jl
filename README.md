# WormWideWebData.jl
[![CI](https://github.com/flavell-lab/WormWideWebData.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/flavell-lab/WormWideWebData.jl/actions/workflows/ci.yml)

`WormWideWebData.jl` provides tools to:

- sync paper metadata from the WormWideWeb reference repository,
- download dataset bundles from Zenodo/Dryad,
- validate HDF5 dataset integrity,
- package processed HDF5 datasets with checksum manifests,
- transform source files into normalized JSON/HDF5 outputs.

Input data to the package:
- datasets: datasets were acquired and processed using the [ANTSUN]([url](https://github.com/flavell-lab/AtanasKim-Cell2023)) pipeline
- analysis results (if encoding info is available): [CePNEMAnalysis.jl](https://github.com/flavell-lab/CePNEMAnalysis.jl)
- NeuroPAL labels (if identity/labeling info is available): [NeuroPALData.jl](https://github.com/flavell-lab/NeuroPALData.jl) 

## Installation

From Julia:

```julia
using Pkg
Pkg.develop(path=".")
```

Or add from a remote git URL if this repository is hosted.

## Quick Start
### Reference data
The data sources are defined in `activity/papers.json` of https://github.com/flavell-lab/WormWideWeb-data  
See the `WormWideWeb-data` repo for more information on how to add new papers/datasets.


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
The following command automatically pulls the latest reference data from the `WormWideWeb-data` repo and downloads files from respective repositories. Then it loads the data and, if present, encoding data and neuropal label. Finally, the function generates the json files for the web.
```julia
generate_all_paper_json(
    "/www-data/data/",
    "/www-data/"
)
```

### Validating and packaging processed HDF5 files
Use `check_h5_datasets_for_paper_json` to validate every direct `.h5` file in a
directory against the integrity checks required before paper JSON generation.

```julia
using WormWideWebData

path_dir_datasets = "/www-data/atanas_kim_2023/datasets"

check_h5_datasets_for_paper_json(path_dir_datasets)
```

Use `package_h5_datasets` to run the same validation, write
`h5_sha256.csv`, and create a flat `tar.bz2` archive containing only the `.h5`
files plus the checksum CSV. The default archive name is
`processed_h5.tar.bz2`; a relative archive name is saved inside the dataset
directory.

```julia
package_h5_datasets(path_dir_datasets)
package_h5_datasets(path_dir_datasets, "custom_h5_bundle.tar.bz2")
```

After extraction, the archive members are at the top level:

```text
dataset_a.h5
dataset_b.h5
h5_sha256.csv
```

## Docker + Cloud Run
This repository includes:
- `Dockerfile` for a reproducible Julia runtime.
- `scripts/wwd_cli.jl` CLI wrapper for all JSON-generation features.

### Build the image
```bash
docker build -t wormwidewebdata:latest .
```

### CLI help
```bash
docker run --rm wormwidewebdata:latest --help
```

### 1) Generate all paper JSON files
This runs metadata sync + dataset download + JSON generation:
```bash
docker run --rm \
  -v "$PWD/output:/output" \
  -v "$PWD/workspace:/workspace" \
  wormwidewebdata:latest \
  all-json /output /workspace
```

### 2) Generate encoding JSON/HDF5 files
```bash
docker run --rm \
  -v "$PWD/workspace:/workspace" \
  wormwidewebdata:latest \
  encoding-files \
  /workspace/kfc_encoding_h5 \
  /workspace/analysis_dict.jld2 \
  /workspace/fit_results.jld2 \
  /workspace/relative_encoding_strength.jld2
```

### 3) Generate Neuropal label JSON
```bash
docker run --rm \
  -v "$PWD/workspace:/workspace" \
  wormwidewebdata:latest \
  neuropal-json \
  /workspace \
  /workspace/dict_neuropal_label.jld2 \
  --overwrite
```

### 4) Generate per-paper dataset JSON files
Prepare a datasets manifest JSON (`/workspace/datasets.json`) as an array of dataset objects or `{"datasets": [...]}`.
```bash
docker run --rm \
  -v "$PWD/output:/output" \
  -v "$PWD/workspace:/workspace" \
  wormwidewebdata:latest \
  paper-json \
  /output \
  /workspace/atanas_kim_2023 \
  atanas_kim_2023 \
  /workspace/datasets.json \
  --encoding-data \
  --neuropal-label
```

### Cloud Run recommendation
Use **Cloud Run Jobs** for batch generation (instead of Cloud Run Services), because generation tasks are finite jobs and do not expose an HTTP server.

Example job creation:
```bash
gcloud run jobs create wormwideweb-generate-all \
  --image us-central1-docker.pkg.dev/PROJECT_ID/REPO/wormwidewebdata:latest \
  --region us-central1 \
  --args all-json,/output,/workspace \
  --task-timeout 3600s \
  --max-retries 2
```

Run the job:
```bash
gcloud run jobs execute wormwideweb-generate-all --region us-central1
```

Switch the same job to another feature by updating `--args`:
```bash
# encoding-files
gcloud run jobs update wormwideweb-generate-all \
  --region us-central1 \
  --args encoding-files,/workspace/kfc_encoding_h5,/workspace/analysis_dict.jld2,/workspace/fit_results.jld2,/workspace/relative_encoding_strength.jld2

# neuropal-json
gcloud run jobs update wormwideweb-generate-all \
  --region us-central1 \
  --args neuropal-json,/workspace,/workspace/dict_neuropal_label.jld2,--overwrite

# paper-json
gcloud run jobs update wormwideweb-generate-all \
  --region us-central1 \
  --args paper-json,/output,/workspace/atanas_kim_2023,atanas_kim_2023,/workspace/datasets.json,--encoding-data,--neuropal-label
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
- `tar` and `pbzip2` (archive extraction and compression),
- `shasum` or `sha256sum` (SHA-256 checksums),
- `md5sum` or `md5` (MD5 checksums),
- `b3sum` (BLAKE3 checksum for some preprocessing paths).

Install these tools and ensure they are available in `PATH` for full functionality.
