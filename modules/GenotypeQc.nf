#!/bin/bash nextflow

process PrepareRuntimeAssets {

input:
  val(runtime_cache_dir)

output:
  path("runtime.ready")

script:
if (params.embedded_runtime) {
  """
  touch runtime.ready
  """
} else {
"""
"$baseDir/scripts/offline_fetch.sh" "${runtime_cache_dir}"
touch runtime.ready
"""
}
}

process ConvertAndFilterVcf {

input:
  tuple path(vcf), val(s_stat), val(sd_thresh), val(ExclusionList), \
      val(InclusionList), val(genome_build),
  val(plink2_executable)
  path(runtime_ready)

output:
  tuple path("*_converted.bed"), path("*_converted.bim"), path("*_converted.fam")

script:
resolved_plink2_executable = plink2_executable ?: "${params.runtime_cache_dir}/bin/plink2"
"""

chr=\$(basename ${vcf} | grep -oE '^chr[0-9XYM]+')

"${resolved_plink2_executable}" \
  --vcf ${vcf} \
  --make-bed \
  --out \${chr}_converted
"""
}


process GenotypeQC {

    input:
  tuple path(bfile), path(bim), path(fam), val(s_stat), val(sd_thresh), val(hwe_threshold), val(qc_maf_threshold), val(ExclusionList), \
      val(InclusionList), val(genome_build)
      path(runtime_ready)
      val(fam_annot)
      val(plink_executable)
      val(plink2_executable)
      val(reference_1000g_folder)
      val(chain_path)
      path(reference_unrelated_samples)
      path(reference_populations)

    output:
      path('outputfolder_gen')
      path('outputfolder_gen/gen_data_QCd/*fam')
      path('1000Gref.afreq.gz')
      path('targetfile.afreq.gz')
      path('outputfolder_gen/gen_data_QCd/SexCheck.txt')

    script:
    // Resolve host runtime defaults locally because optional value inputs may be empty strings.
    resolved_plink2_executable = plink2_executable ?: "${params.runtime_cache_dir}/bin/plink2"
    resolved_plink_executable = plink_executable ?: resolved_plink2_executable
    resolved_reference_1000g_folder = reference_1000g_folder ?: "${params.runtime_cache_dir}/reference_1000g"
    resolved_chain_path = chain_path ?: "${params.runtime_cache_dir}/chain"
    resolved_liftover_executable = params.liftover_executable ?: "${params.runtime_cache_dir}/bin/liftOver"

    reference_1000g_prefix_arg = resolved_reference_1000g_folder ? "--ref_1000g ${resolved_reference_1000g_folder}/1000G_phase3_common_norel" : ""
    fam_arg = fam_annot ? "--fam ${fam_annot}" : ""
    plink_arg = resolved_plink_executable ? "--plink_executable ${resolved_plink_executable}" : ""
    plink2_arg = resolved_plink2_executable ? "--plink2_executable ${resolved_plink2_executable}" : ""
    chain_path_arg = resolved_chain_path ? "--chain_path ${resolved_chain_path}" : ""
    inclusion_arg = InclusionList ? "--inclusion_list \"$InclusionList\"" : ""
    exclusion_arg = ExclusionList ? "--exclusion_list \"${ExclusionList}\"" : ""
    liftover_arg = resolved_liftover_executable ? "--liftover_path \"${resolved_liftover_executable}\"" : ""

    """
    Rscript --vanilla $baseDir/bin/GenQcAndPosAssign.R  \
    --target_bed ${bfile} \
    $fam_arg \
    --genome_build ${genome_build} \
    --sample_list ${reference_unrelated_samples} \
    --pops ${reference_populations} \
    --S_threshold ${s_stat} \
    --SD_threshold ${sd_thresh} \
    --hwe_threshold ${hwe_threshold} \
    --qc_maf_threshold ${qc_maf_threshold} \
    $inclusion_arg \
    $exclusion_arg \
    --output outputfolder_gen \
    $liftover_arg \
    $plink_arg \
    $plink2_arg \
    $reference_1000g_prefix_arg \
    $chain_path_arg
    """
    
}

process MergeBed {

    input:
  tuple file(bed), file(bim), file(fam), val(plink2_executable)
  path(runtime_ready)
      
    output:
      tuple file("chrAll.bed"), file("chrAll.bim"), file("chrAll.fam")

    script:
      resolved_plink2_executable = plink2_executable ?: "${params.runtime_cache_dir}/bin/plink2"
      """
      ls chr*_converted.bed \
      | sed 's/.bed\$//' > mergelist.txt

      "${resolved_plink2_executable}" --pmerge-list mergelist.txt bfile --make-bed --out "chrAll"
      """
}

process RenderReport {

  publishDir "${params.output_dir}", mode: 'copy', overwrite: true

    input:
      tuple path(output_gen), path(fam), path(ref_af), path(target_af), path(sexcheck), val(stresh), val(sdtresh), path(report), val(additional_covariates), path(vcf_filter_outputs), val(genotype_field), val(data_type), val(imputation_filter_enabled)

    output:
      path ('outputfolder_gen/')
      path ('Report_DataQc*')
      path ('CovariatePCs.txt')

    script:
    """
    # Stage VCF filtering output files for the report
    mkdir -p outputfolder_gen/gen_data_summary/vcf_filtering
    if [ -n "${vcf_filter_outputs}" ]; then
      cp -L ${vcf_filter_outputs} outputfolder_gen/gen_data_summary/vcf_filtering/
    fi

    # Make combined covariate file
    Rscript --vanilla $baseDir/bin/MakeCovariateFile.R ${sexcheck} "${additional_covariates}"

    # Make report
    cp -L ${report} notebook.Rmd

    R -e 'library(rmarkdown);rmarkdown::render("notebook.Rmd", "html_document", 
    output_file = "Report_DataQc_${params.cohort_name}.html", 
    params = list(
    dataqc_version = "${workflow.manifest.version}",
    dataset_name = "${params.cohort_name}",
    N = "CovariatePCs.txt", 
    S = ${stresh},
    SD = ${sdtresh},
    data_type = "${data_type}",
    imputation_filter_enabled = ${imputation_filter_enabled ? 'TRUE' : 'FALSE'},
    vcf_maf = ${params.vcf_maf},
    vcf_hwe = ${params.vcf_hwe},
    vcf_imp = ${params.vcf_imp},
    genotype_field = "${genotype_field}",
    imputation_metric_field = "${params.vcf_imp_field}"))'

    """
}

process FilterFinalVcf {

  container { params.embedded_runtime ? null : 'genotypeqc:latest' }
  publishDir "${params.output_dir}/vcf_filtering", mode: 'copy', overwrite: true

    input:
      tuple path(vcf), path(filtered_fam), val(maf), val(vcf_hwe_threshold), val(imputation_th), val(info_field), val(genotype_field), val(data_type), val(enable_imputation_filter)

    output:
      tuple path("*_filtered.vcf.gz"), path("*_filtered.vcf.gz.csi"), path("*_prefilter.stats.txt"), path("*_filtered.stats.txt"), path("*_prefilter.variant_metrics.tsv"), path("*_filtered.variant_metrics.tsv")

    script:
    include_imputation_metric = data_type == 'imputed' && info_field
    imputation_filter_clause = include_imputation_metric && enable_imputation_filter ? " && INFO/${info_field}>=${imputation_th}" : ""
    filter_expression = "INFO/MAF>=${maf} && INFO/HWE>=${vcf_hwe_threshold}${imputation_filter_clause}"
    metric_header = include_imputation_metric ? "CHROM\\tPOS\\tID\\tMAF\\tHWE\\t${info_field}\\tTYPED\\ttyped\\tIMPUTED\\timputed" : "CHROM\\tPOS\\tID\\tMAF\\tHWE\\tTYPED\\ttyped\\tIMPUTED\\timputed"
    metric_format = include_imputation_metric ? "%CHROM\\t%POS\\t%ID\\t%INFO/MAF\\t%INFO/HWE\\t%INFO/${info_field}\\t%INFO/TYPED\\t%INFO/typed\\t%INFO/IMPUTED\\t%INFO/imputed" : "%CHROM\\t%POS\\t%ID\\t%INFO/MAF\\t%INFO/HWE\\t%INFO/TYPED\\t%INFO/typed\\t%INFO/IMPUTED\\t%INFO/imputed"
    if (genotype_field) {
      metric_header += "\\t${genotype_field}"
      metric_format += "\\t%INFO/${genotype_field}"
    }
    """
    chr=\$(basename ${vcf} | grep -oE '^chr[0-9XYM]+')
    awk '{print \$2}' ${filtered_fam} | sort -u > iids.txt

    # 1) Filter by QC-passed samples.
    bcftools view \
    -S iids.txt \
    -Ob -o \${chr}_subset.bcf \
    ${vcf}

    # 2) Recalculate cohort-dependent INFO tags.
    bcftools +fill-tags \
    \${chr}_subset.bcf \
    -Ob -o \${chr}_subset.filled.bcf \
    -- -t AC,AN,AF,MAF,HWE

    # 3) Report variant metrics before filtering.
    bcftools stats \${chr}_subset.filled.bcf > \${chr}_prefilter.stats.txt
    printf "${metric_header}\\n" > \${chr}_prefilter.variant_metrics.tsv
    bcftools query -u -f "${metric_format}\\n" \
      \${chr}_subset.filled.bcf >> \${chr}_prefilter.variant_metrics.tsv

    # 4) Apply configured variant filters.
    bcftools view \
    -i "${filter_expression}" \
    -Oz -o \${chr}_filtered.raw.vcf.gz \
    \${chr}_subset.filled.bcf

    # 5) Standardize variant IDs as CHROM:POS_REF_ALT.
    bcftools annotate \
    --set-id '%CHROM:%POS\\_%REF\\_%ALT' \
    -Oz -o \${chr}_filtered.vcf.gz \
    \${chr}_filtered.raw.vcf.gz

    bcftools index \${chr}_filtered.vcf.gz

    # 6) Report post-filtering variant stats.
    bcftools stats \${chr}_filtered.vcf.gz > \${chr}_filtered.stats.txt
    printf "${metric_header}\\n" > \${chr}_filtered.variant_metrics.tsv
    bcftools query -u -f "${metric_format}\\n" \
      \${chr}_filtered.vcf.gz >> \${chr}_filtered.variant_metrics.tsv

    # 7) Cleanup interim files.
    rm -f \${chr}_subset.bcf \${chr}_subset.bcf.csi \${chr}_subset.filled.bcf \${chr}_subset.filled.bcf.csi \${chr}_filtered.raw.vcf.gz \${chr}_filtered.raw.vcf.gz.csi

    """

}


workflow GENOTYPEQC {
    take:
        data
    runtime_ready
        fam
        plink
        plink2
        reference
        chain
    reference_unrelated_samples
    reference_populations

    main:
        GenotypeQc_output_ch = GenotypeQC(
          data, 
          runtime_ready,
          fam,
          plink.ifEmpty { Channel.value(null) }, 
      plink2.ifEmpty { Channel.value(null) }, 
          reference.ifEmpty { Channel.value(null) }, 
          chain.ifEmpty { Channel.value(null) },
          reference_unrelated_samples,
          reference_populations
          )

    emit:
        cleaned_gen_ch = GenotypeQC.out[0]
        cleaned_fam = GenotypeQC.out[1]
        KG_af_ch = GenotypeQC.out[2]
        target_af_ch = GenotypeQC.out[3]
        sexcheck = GenotypeQC.out[4]
}

workflow RENDERREPORT {
    take:
      data

    main:
      Report_output_ch = RenderReport(data)

    emit:
      Geno_output_ch = RenderReport.out[0]
      Report_output_ch = RenderReport.out[1]
      Covariate_PC_ch = RenderReport.out[2]

}

workflow PREPARERUNTIMEASSETS {
    take:
      data

    main:
      PrepareRuntimeAssets_ch = PrepareRuntimeAssets(data)

    emit:
      runtime_ready = PrepareRuntimeAssets_ch

}

workflow CONVERTANDFILTERVCF {
    take:
      data
      runtime_ready

    main:
      VcfFilter_ch = ConvertAndFilterVcf(data, runtime_ready)

    emit:
      VcfFilter_output_ch = VcfFilter_ch

}

workflow MERGEBED {
    take:
      data
      runtime_ready

    main:
      MergeBed_ch = MergeBed(data, runtime_ready)

    emit:
      MergeBed_output_ch = MergeBed_ch

}

workflow FILTERFINALVCF {
    take:
      data

    main:
      FilterFinalVcf_ch = FilterFinalVcf(data)

    emit:
      FilterFinalVcf_output_ch = FilterFinalVcf_ch

}