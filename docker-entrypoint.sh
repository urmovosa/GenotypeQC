#!/usr/bin/env bash
set -euo pipefail

export NXF_HOME="${NXF_HOME:-/workspace/.nextflow}"
export NXF_OFFLINE="${NXF_OFFLINE:-true}"

mkdir -p "$NXF_HOME"

if [[ $# -eq 0 ]]; then
  set -- nextflow run /opt/genotypeqc/main.nf -profile single_docker
else
  case "$1" in
    bash|sh|nextflow|R|Rscript|python|python3)
      exec "$@"
      ;;
  esac

  use_default_profile=1
  for arg in "$@"; do
    if [[ "$arg" == "-profile" || "$arg" == -profile=* ]]; then
      use_default_profile=0
      break
    fi
  done

  if [[ "$1" == -* ]]; then
    if [[ $use_default_profile -eq 1 ]]; then
      set -- nextflow run /opt/genotypeqc/main.nf -profile single_docker "$@"
    else
      set -- nextflow run /opt/genotypeqc/main.nf "$@"
    fi
  fi
fi

exec "$@"