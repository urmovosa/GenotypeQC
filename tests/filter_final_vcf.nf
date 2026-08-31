#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

params.output_dir = params.output_dir ?: "$baseDir/output"
params.embedded_runtime = true

include { FilterFinalVcf } from '../modules/GenotypeQc.nf'

workflow {
  filter_input_ch = Channel.of(tuple(
    file(params.vcf),
    file(params.fam),
    params.maf as Double,
    params.hwe as Double,
    params.imp as Double,
    params.info_field,
    '',
    params.data_type,
    params.enable_imputation_filter.toString().toBoolean()
  ))

  FilterFinalVcf(filter_input_ch)
}