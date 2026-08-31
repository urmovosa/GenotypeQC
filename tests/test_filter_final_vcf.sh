#!/usr/bin/env bash

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "${test_dir}"' EXIT

run_case() {
  local case_name="$1"
  local source_vcf="$2"
  local data_type="$3"
  local enable_imputation_filter="$4"
  local expected_records="$5"
  local case_dir="${test_dir}/${case_name}"

  mkdir -p "${case_dir}"
  bgzip -c "${source_vcf}" > "${case_dir}/chr1.vcf.gz"
  tabix -p vcf "${case_dir}/chr1.vcf.gz"

  NXF_SYNTAX_PARSER=v1 nextflow run "${repo_dir}/tests/filter_final_vcf.nf" \
    --vcf "${case_dir}/chr1.vcf.gz" \
    --fam "${repo_dir}/tests/fixtures/minimal.fam" \
    --output_dir "${case_dir}/output" \
    --maf 0 \
    --hwe 0 \
    --imp 0.8 \
    --info_field R2 \
    --data_type "${data_type}" \
    --enable_imputation_filter "${enable_imputation_filter}" \
    -work-dir "${case_dir}/work"

  local filtered_vcf="${case_dir}/output/vcf_filtering/chr1_filtered.vcf.gz"
  local actual_records
  actual_records="$(bcftools view -H "${filtered_vcf}" | wc -l | tr -d ' ')"
  if [[ "${actual_records}" != "${expected_records}" ]]; then
    echo "${case_name}: expected ${expected_records} records, found ${actual_records}" >&2
    return 1
  fi

  if [[ "${data_type}" == "wgs" ]]; then
    local metrics="${case_dir}/output/vcf_filtering/chr1_prefilter.variant_metrics.tsv"
    if head -n 1 "${metrics}" | grep -q $'\tR2\t'; then
      echo "${case_name}: WGS metrics unexpectedly contain R2" >&2
      return 1
    fi
  fi
}

run_case \
  imputed_enabled \
  "${repo_dir}/tests/fixtures/minimal_imputed.vcf" \
  imputed true 1

run_case \
  imputed_disabled \
  "${repo_dir}/tests/fixtures/minimal_imputed.vcf" \
  imputed false 2

run_case \
  wgs_without_r2 \
  "${repo_dir}/tests/fixtures/minimal_wgs.vcf" \
  wgs true 2

echo "FilterFinalVcf regression tests passed."