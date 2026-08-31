#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF >&2
Usage: $0 [--platform PLATFORM] [--restricted-assets-only|--skip-restricted-assets] [RUNTIME_CACHE_DIR]

Supported PLATFORM values:
  linux-x86_64
  darwin-arm64
  darwin-x86_64

When --platform is omitted, the current host platform is used.

Use --restricted-assets-only to stage only UCSC LiftOver and chain files.
Use --skip-restricted-assets when building the public container image.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

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

TARGET_PLATFORM="${GENOTYPEQC_TARGET_PLATFORM:-$(normalize_platform "$(uname -s)" "$(uname -m)")}"
RUNTIME_CACHE_DIR=""
RESTRICTED_ASSETS_ONLY=false
SKIP_RESTRICTED_ASSETS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
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
    --restricted-assets-only)
      RESTRICTED_ASSETS_ONLY=true
      shift
      ;;
    --skip-restricted-assets)
      SKIP_RESTRICTED_ASSETS=true
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      if [[ -n "${RUNTIME_CACHE_DIR}" ]]; then
        echo "Only one runtime cache directory may be provided." >&2
        usage
        exit 1
      fi
      RUNTIME_CACHE_DIR="$1"
      shift
      ;;
  esac
done

if [[ "${RESTRICTED_ASSETS_ONLY}" == true && "${SKIP_RESTRICTED_ASSETS}" == true ]]; then
  echo "--restricted-assets-only and --skip-restricted-assets cannot be used together." >&2
  exit 1
fi

RUNTIME_CACHE_DIR="${RUNTIME_CACHE_DIR:-${REPO_ROOT}/.runtime_downloads}"

detect_plink2_url() {
  case "${TARGET_PLATFORM}" in
    darwin-arm64)
      printf '%s\n' "https://s3.amazonaws.com/plink2-assets/alpha7/plink2_mac_arm64_20260504.zip"
      ;;
    darwin-x86_64)
      printf '%s\n' "https://s3.amazonaws.com/plink2-assets/alpha7/plink2_mac_20260504.zip"
      ;;
    linux-x86_64)
      printf '%s\n' "https://s3.amazonaws.com/plink2-assets/alpha7/plink2_linux_x86_64_20260504.zip"
      ;;
    *)
      echo "Unsupported platform for automatic PLINK 2 download: ${TARGET_PLATFORM}" >&2
      exit 1
      ;;
  esac
}

detect_liftover_url() {
  case "${TARGET_PLATFORM}" in
    darwin-arm64)
      printf '%s\n' "https://hgdownload.soe.ucsc.edu/admin/exe/macOSX.arm64/liftOver"
      ;;
    darwin-x86_64)
      printf '%s\n' "https://hgdownload.soe.ucsc.edu/admin/exe/macOSX.x86_64/liftOver"
      ;;
    linux-x86_64)
      printf '%s\n' "https://hgdownload.soe.ucsc.edu/admin/exe/linux.x86_64/liftOver"
      ;;
    *)
      echo "Unsupported platform for automatic liftOver download: ${TARGET_PLATFORM}" >&2
      exit 1
      ;;
  esac
}

binary_runs_on_host() {
  local target="$1"
  shift || true

  if [[ ! -x "${target}" ]]; then
    return 1
  fi

  "${target}" "$@" >/dev/null 2>&1
  local status="$?"
  [[ "${status}" -ne 126 && "${status}" -ne 127 ]]
}

download_zip_binary() {
  local url="$1"
  local target="$2"
  local member="$3"

  if binary_runs_on_host "${target}" --version; then
    return 0
  fi

  rm -f "${target}"

  local target_dir
  target_dir="$(dirname "${target}")"
  mkdir -p "${target_dir}"
  local archive="${target_dir}/${member}.zip"
  curl -fsSL "${url}" -o "${archive}"
  unzip -jo "${archive}" "${member}" -d "${target_dir}" >/dev/null
  rm -f "${archive}"
  chmod +x "${target_dir}/${member}"

  if [[ "${target}" != "${target_dir}/${member}" ]]; then
    mv -f "${target_dir}/${member}" "${target}"
    chmod +x "${target}"
  fi
}

download_executable_if_needed() {
  local url="$1"
  local target="$2"

  if binary_runs_on_host "${target}"; then
    return 0
  fi

  rm -f "${target}"
  mkdir -p "$(dirname "${target}")"
  curl -fsSL "${url}" -o "${target}"
  chmod +x "${target}"
}

download_file_if_missing() {
  local url="$1"
  local target="$2"

  if [[ -f "${target}" ]]; then
    return 0
  fi

  mkdir -p "$(dirname "${target}")"
  curl -fsSL "${url}" -o "${target}"
}

mkdir -p "${RUNTIME_CACHE_DIR}/bin" \
         "${RUNTIME_CACHE_DIR}/chain" \
         "${RUNTIME_CACHE_DIR}/reference_1000g"

if [[ "${RESTRICTED_ASSETS_ONLY}" == false ]]; then
  download_zip_binary "$(detect_plink2_url)" "${RUNTIME_CACHE_DIR}/bin/plink2" "plink2"
  ln -sf plink2 "${RUNTIME_CACHE_DIR}/bin/plink"

  if [[ ! -f "${RUNTIME_CACHE_DIR}/reference_1000g/1000G_phase3_common_norel.bed" || \
        ! -f "${RUNTIME_CACHE_DIR}/reference_1000g/1000G_phase3_common_norel.bim" || \
        ! -f "${RUNTIME_CACHE_DIR}/reference_1000g/1000G_phase3_common_norel.fam" ]]; then
    if ! command -v Rscript >/dev/null 2>&1; then
      echo "Rscript is required to download the 1000G reference cache." >&2
      exit 1
    fi

    Rscript -e "if (!requireNamespace('bigsnpr', quietly = TRUE)) stop('bigsnpr is required in the active R environment'); library(bigsnpr); download_1000G('${RUNTIME_CACHE_DIR}/reference_1000g')"
  fi
fi

if [[ "${SKIP_RESTRICTED_ASSETS}" == false ]]; then
  download_executable_if_needed "$(detect_liftover_url)" "${RUNTIME_CACHE_DIR}/bin/liftOver"

  download_file_if_missing \
    "https://hgdownload.soe.ucsc.edu/goldenPath/hg19/liftOver/hg19ToHg38.over.chain.gz" \
    "${RUNTIME_CACHE_DIR}/chain/hg19ToHg38.over.chain.gz"

  download_file_if_missing \
    "https://hgdownload.soe.ucsc.edu/goldenPath/hg38/liftOver/hg38ToHg19.over.chain.gz" \
    "${RUNTIME_CACHE_DIR}/chain/hg38ToHg19.over.chain.gz"
fi

cat <<EOF
Runtime assets prepared at:
  ${RUNTIME_CACHE_DIR}

Target platform:
- ${TARGET_PLATFORM}

Cached assets:
- unrestricted runtime: $([[ "${RESTRICTED_ASSETS_ONLY}" == true ]] && echo "not requested" || echo "${RUNTIME_CACHE_DIR}/bin/plink2 and ${RUNTIME_CACHE_DIR}/reference_1000g/")
- restricted assets: $([[ "${SKIP_RESTRICTED_ASSETS}" == true ]] && echo "not requested" || echo "${RUNTIME_CACHE_DIR}/bin/liftOver and ${RUNTIME_CACHE_DIR}/chain/")

Use this cache for later offline runs with:
  --runtime_cache_dir ${RUNTIME_CACHE_DIR}
EOF
