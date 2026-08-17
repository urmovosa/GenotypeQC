#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF >&2
Usage: $0 [--bundle-dir PATH] [--platform PLATFORM] [--container-source URI] [--development-runtime-cache]

Prepare an offline staging bundle containing:
- a local SIF image for Apptainer/Singularity runs
- a warmed Nextflow home directory for disconnected execution
- an env helper and summary file for moving the bundle offline

Supported PLATFORM values:
  linux-x86_64
  darwin-arm64
  darwin-x86_64

Defaults:
- bundle dir: <repo>/.offline_bundle
- platform: current host platform
- container source: oras://ghcr.io/urmovosa/genotypeqc-sif:latest

The script reports whether Java, Nextflow, Apptainer/Singularity, and R are
available on the staging machine. The public image contains R and all
pipeline-specific runtime assets; R on the host is only needed when preparing
the optional development runtime cache. The script does not install general
runtimes.
EOF
}

normalize_platform() {
  case "$1:$2" in
    Darwin:arm64)
      printf '%s\n' "darwin-arm64"
      ;;
    Darwin:x86_64)
      printf '%s\n' "darwin-x86_64"
      ;;
    Linux:x86_64|Linux:amd64)
      printf '%s\n' "linux-x86_64"
      ;;
    *)
      echo "Unsupported platform: $1 $2" >&2
      exit 1
      ;;
  esac
}

resolve_cmd() {
  local candidate
  for candidate in "$@"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOST_PLATFORM="$(normalize_platform "$(uname -s)" "$(uname -m)")"

BUNDLE_DIR="${REPO_ROOT}/.offline_bundle"
TARGET_PLATFORM="${GENOTYPEQC_TARGET_PLATFORM:-${HOST_PLATFORM}}"
CONTAINER_SOURCE="${GENOTYPEQC_CONTAINER_SOURCE:-oras://ghcr.io/urmovosa/genotypeqc-sif:latest}"
PREPARE_DEVELOPMENT_RUNTIME_CACHE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --bundle-dir)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --bundle-dir" >&2
        usage
        exit 1
      fi
      BUNDLE_DIR="$2"
      shift 2
      ;;
    --bundle-dir=*)
      BUNDLE_DIR="${1#*=}"
      shift
      ;;
    --platform)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --platform" >&2
        usage
        exit 1
      fi
      TARGET_PLATFORM="$2"
      shift 2
      ;;
    --platform=*)
      TARGET_PLATFORM="${1#*=}"
      shift
      ;;
    --container-source)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --container-source" >&2
        usage
        exit 1
      fi
      CONTAINER_SOURCE="$2"
      shift 2
      ;;
    --container-source=*)
      CONTAINER_SOURCE="${1#*=}"
      shift
      ;;
    --development-runtime-cache)
      PREPARE_DEVELOPMENT_RUNTIME_CACHE=true
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      echo "Unexpected argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

RUNTIME_CACHE_DIR="${BUNDLE_DIR}/runtime_cache"
CONTAINER_DIR="${BUNDLE_DIR}/containers"
CONTAINER_IMAGE_PATH="${CONTAINER_DIR}/genotypeqc_latest.sif"
NEXTFLOW_HOME_DIR="${BUNDLE_DIR}/nextflow_home"
SINGULARITY_CACHE_DIR="${BUNDLE_DIR}/singularity_cache"
ENV_FILE="${BUNDLE_DIR}/offline-env.sh"
SUMMARY_FILE="${BUNDLE_DIR}/STAGING_SUMMARY.txt"

mkdir -p "${BUNDLE_DIR}" "${CONTAINER_DIR}" "${SINGULARITY_CACHE_DIR}"

JAVA_BIN="$(resolve_cmd java || true)"
NEXTFLOW_BIN="${NEXTFLOW_BIN:-$(resolve_cmd nextflow || true)}"
APPTAINER_BIN="${APPTAINER_BIN:-$(resolve_cmd apptainer singularity || true)}"
RSCRIPT_BIN="${RSCRIPT_BIN:-$(resolve_cmd Rscript || true)}"

java_status="missing"
nextflow_status="missing"
apptainer_status="missing"
r_status="missing"

if [[ -n "${JAVA_BIN}" ]]; then
  java_status="found at ${JAVA_BIN}"
fi

if [[ -n "${NEXTFLOW_BIN}" ]]; then
  nextflow_status="found at ${NEXTFLOW_BIN}"
fi

if [[ -n "${APPTAINER_BIN}" ]]; then
  apptainer_status="found at ${APPTAINER_BIN}"
fi

if [[ -n "${RSCRIPT_BIN}" ]]; then
  r_status="found at ${RSCRIPT_BIN}"
fi

runtime_cache_status="not requested (container image provides runtime assets)"
container_status="not started"
nextflow_home_status="not started"
overall_status="ready"

if [[ "${TARGET_PLATFORM}" != "linux-x86_64" ]]; then
  container_status="unsupported target platform (published SIF is linux-x86_64 only)"
  overall_status="incomplete"
fi

if [[ "${PREPARE_DEVELOPMENT_RUNTIME_CACHE}" == true ]]; then
  if "${SCRIPT_DIR}/offline_fetch.sh" --platform "${TARGET_PLATFORM}" "${RUNTIME_CACHE_DIR}"; then
    runtime_cache_status="ready at ${RUNTIME_CACHE_DIR}"
  else
    runtime_cache_status="failed"
    overall_status="incomplete"
  fi
fi

if [[ "${TARGET_PLATFORM}" == "linux-x86_64" ]]; then
  if [[ -z "${APPTAINER_BIN}" ]]; then
    container_status="missing Apptainer/Singularity on the staging host"
    overall_status="incomplete"
  elif [[ -f "${CONTAINER_IMAGE_PATH}" ]]; then
    container_status="ready at ${CONTAINER_IMAGE_PATH}"
  elif APPTAINER_CACHEDIR="${SINGULARITY_CACHE_DIR}" "${APPTAINER_BIN}" pull "${CONTAINER_IMAGE_PATH}" "${CONTAINER_SOURCE}"; then
    container_status="ready at ${CONTAINER_IMAGE_PATH}"
  else
    container_status="failed to pull ${CONTAINER_SOURCE}"
    overall_status="incomplete"
  fi
fi

if [[ -z "${NEXTFLOW_BIN}" ]]; then
  nextflow_home_status="missing Nextflow on the staging host"
  overall_status="incomplete"
elif [[ -z "${JAVA_BIN}" ]]; then
  nextflow_home_status="missing Java on the staging host"
  overall_status="incomplete"
elif NXF_HOME="${NEXTFLOW_HOME_DIR}" "${NEXTFLOW_BIN}" -version >/dev/null; then
  nextflow_home_status="ready at ${NEXTFLOW_HOME_DIR}"
else
  nextflow_home_status="failed to initialize ${NEXTFLOW_HOME_DIR}"
  overall_status="incomplete"
fi

cat > "${ENV_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

GENOTYPEQC_BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export NXF_OFFLINE=TRUE
export NXF_HOME="${GENOTYPEQC_BUNDLE_DIR}/nextflow_home"
export SINGULARITY_CACHEDIR="${GENOTYPEQC_BUNDLE_DIR}/singularity_cache"
export APPTAINER_CACHEDIR="${GENOTYPEQC_BUNDLE_DIR}/singularity_cache"
export GENOTYPEQC_CONTAINER_IMAGE="${GENOTYPEQC_BUNDLE_DIR}/containers/genotypeqc_latest.sif"
EOF
chmod +x "${ENV_FILE}"

cat > "${SUMMARY_FILE}" <<EOF
GenotypeQC offline staging summary
==================================

Overall status: ${overall_status}

Repository checkout:
- ${REPO_ROOT}

Bundle directory:
- ${BUNDLE_DIR}

Platforms:
- staging host: ${HOST_PLATFORM}
- target: ${TARGET_PLATFORM}

General runtimes on the staging host:
- Java: ${java_status}
- Nextflow: ${nextflow_status}
- Apptainer/Singularity: ${apptainer_status}
- Rscript: ${r_status}

Prepared assets:
- runtime cache: ${runtime_cache_status}
- local SIF image: ${container_status}
- Nextflow home: ${nextflow_home_status}
- env helper: ${ENV_FILE}

If you move to a separate offline machine, copy:
- the repository checkout
- the entire bundle directory above
- the Nextflow launcher if the offline machine does not already provide nextflow

Recommended offline run flow:
1. Copy the repository and bundle to the offline machine.
2. Source the env helper: source /path/to/offline-env.sh
3. Run the pipeline with local assets, for example:

   NXF_SYNTAX_PARSER=v1 nextflow run /path/to/GenotypeQC/main.nf \
     -profile slurm,singularity \
     --container_image "\$GENOTYPEQC_CONTAINER_IMAGE" \
     --vcf /absolute/path/to/imputed_vcfs \
     --cohort_name cohort_a \
     --genome_build GRCh38 \
     --output_dir /absolute/path/to/results/cohort_a \
     -resume

See scripts/OFFLINE.md for more detail.
EOF

cat "${SUMMARY_FILE}"

if [[ "${overall_status}" != "ready" ]]; then
  exit 1
fi