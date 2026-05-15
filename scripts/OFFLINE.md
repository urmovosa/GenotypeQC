# Offline Host And Scheduler Use

If you use the bundled Docker image, the runtime assets are already inside the image. This document is for host or scheduler runs outside that image.

## Runtime Cache Layout

Host runs use a persistent runtime cache. The default location is `.runtime_downloads/` in the repo, but you can override it with `--runtime_cache_dir`.

Expected layout:

```text
RUNTIME_CACHE/
  bin/
    plink2
    liftOver
  reference_1000g/
    1000G_phase3_common_norel.bed
    1000G_phase3_common_norel.bim
    1000G_phase3_common_norel.fam
  chain/
    hg19ToHg38.over.chain.gz
    hg38ToHg19.over.chain.gz
```

The pipeline uses the cached `plink2` binary for both PLINK-compatible and PLINK 2 calls unless you override `--plink_executable` explicitly.

## Preparing The Cache Online

Choose one of the following:

1. Run the pipeline once while online. Missing runtime assets are downloaded into the cache automatically.
2. Preload the cache with `scripts/offline_fetch.sh /path/to/runtime_cache`.

The helper script downloads:

- PLINK 2 for the current host platform
- UCSC `liftOver` for the current host platform
- `hg19ToHg38` and `hg38ToHg19` chain files
- the 1000G reference via `bigsnpr::download_1000G()`

## Moving To An Offline Host

Copy these items to the offline machine:

- the repository checkout
- the prepared runtime cache directory
- the Nextflow executable if it is not already installed locally
- `singularity_img/` if you intend to use the `singularity` profile offline

## Running Offline

Example host run:

```bash
export NXF_OFFLINE=TRUE
export NXF_HOME=/path/to/nxf_home

NXF_SYNTAX_PARSER=v1 nextflow run main.nf \
  -profile local_vm \
  --vcf /absolute/path/to/imputed_vcfs \
  --cohort_name cohort_a \
  --genome_build GRCh38 \
  --runtime_cache_dir /absolute/path/to/runtime_cache \
  --output_dir /absolute/path/to/results/cohort_a \
  -resume
```

Example scheduler run:

```bash
export NXF_OFFLINE=TRUE
export NXF_HOME=/path/to/nxf_home
export SINGULARITY_CACHEDIR=/path/to/singularitycache

NXF_SYNTAX_PARSER=v1 nextflow run main.nf \
  -profile slurm,singularity \
  --vcf /absolute/path/to/imputed_vcfs \
  --cohort_name cohort_a \
  --genome_build GRCh38 \
  --runtime_cache_dir /absolute/path/to/runtime_cache \
  --output_dir /absolute/path/to/results/cohort_a \
  -resume
```

If you keep the standard cache layout, you do not need to pass `--plink_executable`, `--plink2_executable`, `--reference_1000g_folder`, `--chain_path`, or `--liftover_executable` separately.
