FROM julia:1.11-bookworm

ENV JULIA_PROJECT=/app \
    JULIA_DEPOT_PATH=/usr/local/julia-depot \
    JULIA_NUM_THREADS=auto

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    bzip2 \
    coreutils \
    perl \
    b3sum \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Cache dependency resolution first for faster rebuilds.
COPY Project.toml Manifest.toml ./
RUN julia --project=/app -e 'using Pkg; Pkg.instantiate()'

COPY src ./src
COPY scripts/wwd_cli.jl ./scripts/wwd_cli.jl
COPY README.md ./README.md
RUN julia --project=/app -e 'using Pkg; Pkg.precompile()'

RUN useradd --create-home --uid 10001 appuser \
    && mkdir -p /workspace /output \
    && chown -R appuser:appuser /app /workspace /output /usr/local/julia-depot

USER appuser

ENTRYPOINT ["julia", "--project=/app", "/app/scripts/wwd_cli.jl"]
CMD ["--help"]
