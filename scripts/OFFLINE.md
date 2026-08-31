# Offline Host And Scheduler Use

If you use the bundled Docker image, the runtime assets are already inside the image. This document is for host or scheduler runs outside that image, especially on privacy-sensitive clusters that must stay offline during analysis.

## Recommended Staging Flow

Use the staging helper on a connected machine before you move to the offline environment:

```bash
scripts/offline_stage.sh --platform linux-x86_64
```

By default this writes a bundle to `.offline_bundle/` in the repository checkout. The bundle contains:

- `containers/genotypeqc_latest.sif` for Apptainer/Singularity runs
- `offline_runtime/` with UCSC LiftOver and chain files for the local offline deployment
- `nextflow_home/` warmed while still online
- `offline-env.sh` with the offline environment variables
- `STAGING_SUMMARY.txt` with copy and run instructions

The public image contains R, PLINK2, and the 1000G reference. The staging bundle separately retrieves UCSC LiftOver and chain files because their redistribution terms are more restrictive. Do not republish `offline_runtime/` without confirming that the intended use complies with UCSC's terms.

The helper does not install general runtimes. Instead it reports whether Java, Nextflow, Apptainer or Singularity, and R are present on the staging host and tells you which pieces could not be prepared. Java, Nextflow, and Apptainer or Singularity are required on both the staging and offline hosts. R is only required on the host for development-mode runs.

The recommended target for an offline cluster is `linux-x86_64`. Stage on a connected Linux x86_64 machine whenever possible so the downloaded helper binaries match the cluster.

## What The Bundle Prepares

The staging helper pulls the published SIF image locally, prepares the local UCSC LiftOver assets, and warms the required Nextflow runtime. The public image provides PLINK2 and the 1000G reference; only the restricted LiftOver assets remain outside the image.

## Moving To An Offline Host

If the staging machine and the offline machine are different, copy:

- the repository checkout
- the entire `.offline_bundle/` directory produced by `scripts/offline_stage.sh`
- the Nextflow launcher if the offline machine does not already provide `nextflow`

The bundle summary printed by the helper includes the exact staged paths.

## Running Offline

On the offline machine:

```bash
source /path/to/GenotypeQC/.offline_bundle/offline-env.sh
```

Example scheduler run:

```bash
NXF_SYNTAX_PARSER=v1 nextflow run /path/to/GenotypeQC/main.nf \
  -profile slurm,singularity \
  --container_image "$GENOTYPEQC_CONTAINER_IMAGE" \
  --offline_runtime_dir "$GENOTYPEQC_OFFLINE_RUNTIME_DIR" \
  --vcf /absolute/path/to/imputed_vcfs \
  --data_type imputed \
  --cohort_name cohort_a \
  --genome_build GRCh38 \
  --output_dir /absolute/path/to/results/cohort_a \
  -resume
```

## Development-Mode Host Runs

Non-container runs are intended for development. They require R, PLINK2, liftOver, the chain files, and the 1000G reference on the host. To prepare that separate cache, use:

```bash
scripts/offline_stage.sh --platform linux-x86_64 --development-runtime-cache
```

Example development host run:

```bash
NXF_SYNTAX_PARSER=v1 nextflow run /path/to/GenotypeQC/main.nf \
  -profile local_vm \
  --runtime_cache_dir /path/to/GenotypeQC/.offline_bundle/development_runtime_cache \
  --bfile /absolute/path/to/study_prefix \
  --data_type array \
  --cohort_name cohort_a \
  --genome_build GRCh37 \
  --output_dir /absolute/path/to/results/cohort_a \
  -resume
```

If you keep the standard staged layout, you do not need to pass `--plink_executable`, `--plink2_executable`, `--reference_1000g_folder`, `--chain_path`, or `--liftover_executable` separately.

## Runtime-Cache Only Mode

If you only want the development runtime cache and do not want the full offline bundle, you can still run the lower-level helper directly:

```bash
scripts/offline_fetch.sh --platform linux-x86_64 /path/to/runtime_cache
```
