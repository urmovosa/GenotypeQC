#!/usr/bin/env bash
set -euo pipefail

# Helper script to prepare an offline asset directory.
# This script does NOT download assets automatically. It only creates a layout
# and reminds you where to place files.

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/OFFLINE_ROOT" >&2
  exit 1
fi

OFFLINE_ROOT="$1"

mkdir -p "${OFFLINE_ROOT}/plink_executables" \
         "${OFFLINE_ROOT}/1000G_reference" \
         "${OFFLINE_ROOT}/singularity_img" \
         "${OFFLINE_ROOT}/chain_folder"

cat <<'EOF'
Offline layout created.

Place the following files:
- plink and plink2 executables into:   OFFLINE_ROOT/plink_executables/
- 1000G reference files into:          OFFLINE_ROOT/1000G_reference/
- container images (*.sif) into:       OFFLINE_ROOT/singularity_img/
- LiftOver chain files (hg38 only) into: OFFLINE_ROOT/chain_folder/

Then copy/symlink container images into the repo:
  cp -R OFFLINE_ROOT/singularity_img ./singularity_img

See docs/OFFLINE.md for full instructions.
EOF
