#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [RUNTIME_CACHE_DIR]" >&2
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUNTIME_CACHE_DIR="${1:-${REPO_ROOT}/.runtime_downloads}"

detect_plink2_url() {
  case "$(uname -s):$(uname -m)" in
    Darwin:arm64)
      printf '%s\n' "https://s3.amazonaws.com/plink2-assets/alpha7/plink2_mac_arm64_20260504.zip"
      ;;
    Darwin:x86_64)
      printf '%s\n' "https://s3.amazonaws.com/plink2-assets/alpha7/plink2_mac_20260504.zip"
      ;;
    Linux:x86_64|Linux:amd64)
      printf '%s\n' "https://s3.amazonaws.com/plink2-assets/alpha7/plink2_linux_x86_64_20260504.zip"
      ;;
    *)
      echo "Unsupported platform for automatic PLINK 2 download: $(uname -s) $(uname -m)" >&2
      exit 1
      ;;
  esac
}

detect_liftover_url() {
  case "$(uname -s):$(uname -m)" in
    Darwin:arm64)
      printf '%s\n' "https://hgdownload.soe.ucsc.edu/admin/exe/macOSX.arm64/liftOver"
      ;;
    Darwin:x86_64)
      printf '%s\n' "https://hgdownload.soe.ucsc.edu/admin/exe/macOSX.x86_64/liftOver"
      ;;
    Linux:x86_64|Linux:amd64)
      printf '%s\n' "https://hgdownload.soe.ucsc.edu/admin/exe/linux.x86_64/liftOver"
      ;;
    *)
      echo "Unsupported platform for automatic liftOver download: $(uname -s) $(uname -m)" >&2
      exit 1
      ;;
  esac
}

download_zip_binary() {
  local url="$1"
  local target="$2"
  local member="$3"

  if [[ -x "${target}" ]]; then
    return 0
  fi

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

download_zip_binary "$(detect_plink2_url)" "${RUNTIME_CACHE_DIR}/bin/plink2" "plink2"
ln -sf plink2 "${RUNTIME_CACHE_DIR}/bin/plink"

download_file_if_missing "$(detect_liftover_url)" "${RUNTIME_CACHE_DIR}/bin/liftOver"
chmod +x "${RUNTIME_CACHE_DIR}/bin/liftOver"

download_file_if_missing \
  "https://hgdownload.soe.ucsc.edu/goldenPath/hg19/liftOver/hg19ToHg38.over.chain.gz" \
  "${RUNTIME_CACHE_DIR}/chain/hg19ToHg38.over.chain.gz"

download_file_if_missing \
  "https://hgdownload.soe.ucsc.edu/goldenPath/hg38/liftOver/hg38ToHg19.over.chain.gz" \
  "${RUNTIME_CACHE_DIR}/chain/hg38ToHg19.over.chain.gz"

if [[ ! -f "${RUNTIME_CACHE_DIR}/reference_1000g/1000G_phase3_common_norel.bed" || \
      ! -f "${RUNTIME_CACHE_DIR}/reference_1000g/1000G_phase3_common_norel.bim" || \
      ! -f "${RUNTIME_CACHE_DIR}/reference_1000g/1000G_phase3_common_norel.fam" ]]; then
  if ! command -v Rscript >/dev/null 2>&1; then
    echo "Rscript is required to download the 1000G reference cache." >&2
    exit 1
  fi

  Rscript -e "if (!requireNamespace('bigsnpr', quietly = TRUE)) stop('bigsnpr is required in the active R environment'); library(bigsnpr); download_1000G('${RUNTIME_CACHE_DIR}/reference_1000g')"
fi

cat <<EOF
Runtime cache prepared at:
  ${RUNTIME_CACHE_DIR}

Cached assets:
- ${RUNTIME_CACHE_DIR}/bin/plink2
- ${RUNTIME_CACHE_DIR}/bin/liftOver
- ${RUNTIME_CACHE_DIR}/chain/hg19ToHg38.over.chain.gz
- ${RUNTIME_CACHE_DIR}/chain/hg38ToHg19.over.chain.gz
- ${RUNTIME_CACHE_DIR}/reference_1000g/1000G_phase3_common_norel.*

Use this cache for later offline runs with:
  --runtime_cache_dir ${RUNTIME_CACHE_DIR}
EOF
