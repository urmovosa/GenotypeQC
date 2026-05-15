#!/usr/bin/env bash

#SBATCH --time=48:00:00
#SBATCH -N 1
#SBATCH --ntasks-per-node=1
#SBATCH --mem=8G
#SBATCH --mail-type=BEGIN
#SBATCH --mail-type=END
#SBATCH --mail-type=FAIL
#SBATCH --job-name="GenotypeQC"

set -euo pipefail
set -f

# Replace the module set with the equivalents on your cluster.
module load openjdk/17.0.3_7
module load singularity/3.8.5
module load squashfs/4.4

REPO_DIR="/absolute/path/to/GenotypeQC"
NEXTFLOW_BIN="/absolute/path/to/nextflow"

# Input: set one of these two and remove the other from the command below.
VCF_DIR="/absolute/path/to/imputed_vcfs"
# BFILE_PREFIX="/absolute/path/to/study_prefix"

COHORT_NAME="cohort_a"
GENOME_BUILD="GRCh38"
OUTPUT_DIR="${REPO_DIR}/results/${COHORT_NAME}"
RUNTIME_CACHE_DIR="${REPO_DIR}/.runtime_downloads"

# Keep Nextflow and Singularity caches writable outside your home directory.
export SINGULARITY_CACHEDIR="${REPO_DIR}/singularitycache"
export NXF_HOME="${REPO_DIR}/nextflowcache"

# Uncomment for fully offline reruns after the runtime cache and container image are staged.
# export NXF_OFFLINE=TRUE

NXF_SYNTAX_PARSER=v1 "${NEXTFLOW_BIN}" run "${REPO_DIR}/main.nf" \
  --vcf "${VCF_DIR}" \
  --cohort_name "${COHORT_NAME}" \
  --genome_build "${GENOME_BUILD}" \
  --output_dir "${OUTPUT_DIR}" \
  --runtime_cache_dir "${RUNTIME_CACHE_DIR}" \
  -profile slurm,singularity \
  -resume