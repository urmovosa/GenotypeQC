#!/bin/bash nextflow

process ConvertAndFilterVcf {

input:
  tuple path(vcf), val(s_stat), val(sd_thresh), path(ExclusionList), \
      path(InclusionList), val(genome_build), path(genotype_phenotype), path(snplist),
      file(plink2_executable)

output:
  tuple path("*_HapMap3_filtered.bed"), path("*_HapMap3_filtered.bim"), path("*_HapMap3_filtered.fam")

"""

chr=\$(basename ${vcf} | grep -oE '^chr[0-9XYM]+')
zcat ${snplist} | cut -f1 | tail -n +2 > hapmap3_snplist.txt

${plink2_executable} \
  --vcf ${vcf} \
  --extract hapmap3_snplist.txt \
  --make-bed \
  --out \${chr}_HapMap3_filtered
"""
}


process GenotypeQC {

    input:
  tuple path(bfile), path(bim), path(fam), val(s_stat), val(sd_thresh), val(hwe_threshold), val(qc_maf_threshold), path(ExclusionList), \
      path(InclusionList), val(genome_build), path(genotype_phenotype), path(snplist), file(plink2_executable)
      file(fam_annot)
      file(plink_executable)
      file(reference_1000g_folder)
      file(chain_path)

    output:
      path('outputfolder_gen')
      path('outputfolder_gen/gen_data_QCd/*fam')
      path('1000Gref.afreq.gz')
      path('targetfile.afreq.gz')
      path('outputfolder_gen/gen_data_QCd/SexCheck.txt')

    script:
    if (params.reference_1000g_folder == '')
      reference_1000g_prefix_arg = "--ref_1000g data/1000G_phase3_common_norel"
    else
      reference_1000g_prefix_arg = "--ref_1000g $reference_1000g_folder/1000G_phase3_common_norel"

    fam_arg = (params.fam != '') ? "--fam $fam_annot" : ""
    plink_arg = (params.plink_executable != '') ? "--plink_executable $plink_executable" : ""
    plink2_arg = (params.plink2_executable != '') ? "--plink2_executable $plink2_executable" : ""
    chain_path_arg = (params.chain_path != '') ? "--chain_path $chain_path" : ""

    """
    Rscript --vanilla $baseDir/bin/GenQcAndPosAssign.R  \
    --target_bed ${bfile} \
    $fam_arg \
    --genome_build ${genome_build} \
    --sample_list $baseDir/data/unrelated_reference_samples_ids.txt \
    --pops $baseDir/data/1000G_pops.txt \
    --S_threshold ${s_stat} \
    --SD_threshold ${sd_thresh} \
    --hwe_threshold ${hwe_threshold} \
    --qc_maf_threshold ${qc_maf_threshold} \
    --gen_phe ${genotype_phenotype} \
    --inclusion_list "${InclusionList}" \
    --exclusion_list "${ExclusionList}" \
    --output outputfolder_gen \
    --liftover_path $baseDir/bin/liftOver \
    $plink_arg \
    $plink2_arg \
    $reference_1000g_prefix_arg \
    $chain_path_arg
    """
    
}

process MergeBed {

    input:
      tuple file(bed), file(bim), file(fam)
      
    output:
      tuple file("chrAll.bed"), file("chrAll.bim"), file("chrAll.fam")

    script:
      """
      ls chr*_HapMap3_filtered.bed \
      | sed 's/.bed\$//' > mergelist.txt

      plink2 --merge-list mergelist.txt --make-bed --out "chrAll"
      """
}

process RenderReport {

  publishDir "${params.output_dir}", mode: 'copy', overwrite: true

    input:
      tuple path(output_gen), path(fam), path(ref_af), path(target_af), path(sexcheck), val(stresh), val(sdtresh), path(report), path(additional_covariates), path(vcf_filter_outputs)

    output:
      path ('outputfolder_gen/')
      path ('Report_DataQc*')
      path ('CovariatePCs.txt')

    script:
    """
    # Stage VCF filtering output files for the report
    mkdir -p outputfolder_gen/gen_data_summary/vcf_filtering
    cp -L ${vcf_filter_outputs} outputfolder_gen/gen_data_summary/vcf_filtering/

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
    SD = ${sdtresh}))'

    """
}

process FilterFinalVcf {

    container 'quay.io/eqtlgen/eqtlgenimpute:v0.2'
  publishDir "${params.output_dir}/vcf_filtering", mode: 'copy', overwrite: true

    input:
      tuple path(vcf), path(filtered_fam), path(snplist), val(maf), val(vcf_hwe_threshold), val(imputation_th), val(info_field)

    output:
      tuple path("*_filtered.vcf.gz"), path("*_filtered.vcf.gz.csi"), path("*_prefilter.stats.txt"), path("*_filtered.stats.txt"), path("*_prefilter.variant_metrics.tsv"), path("*_filtered.variant_metrics.tsv")

    script:
    """
    chr=\$(basename ${vcf} | grep -oE '^chr[0-9XYM]+')
    zcat ${snplist} | cut -f1 | tail -n +2 > hapmap3_snplist.txt

    awk '{print \$2}' ${filtered_fam} | sort -u > iids.txt

    # 1) Filter by HapMap3 variants and QC-passed samples.
    bcftools view \
    -S iids.txt \
    -T hapmap3_snplist.txt \
    -Ob -o \${chr}_subset.bcf \
    ${vcf}

    # 2) Recalculate INFO tags (MAF, WHE, imputation quality score).
    bcftools +fill-tags \
    \${chr}_subset.bcf \
    -Ob -o \${chr}_subset.filled.bcf \
    -- -t AC,AN,AF,MAF,HWE

    # 3) Report variant stats (MAF, HWE, imputation quality) before filtering.
    bcftools stats \${chr}_subset.filled.bcf > \${chr}_prefilter.stats.txt
    printf "CHROM\\tPOS\\tID\\tMAF\\tHWE\\t%s\\n" "${info_field}" > \${chr}_prefilter.variant_metrics.tsv
    bcftools query \
    -f "%CHROM\\t%POS\\t%ID\\t%INFO/MAF\\t%INFO/HWE\\t%INFO/${info_field}\\n" \
    \${chr}_subset.filled.bcf >> \${chr}_prefilter.variant_metrics.tsv

    # 4) Apply filters (MAF, HWE and imputation quality thresholds).
    bcftools view \
    -i "INFO/MAF>=${maf} && INFO/HWE>=${vcf_hwe_threshold} && INFO/${info_field}>=${imputation_th}" \
    -Oz -o \${chr}_filtered.raw.vcf.gz \
    \${chr}_subset.filled.bcf

    # 5) Standardize variant IDs as CHROM:POS_REF_ALT.
    bcftools annotate \
    --set-id '%CHROM:%POS_%REF_%ALT' \
    -Oz -o \${chr}_filtered.vcf.gz \
    \${chr}_filtered.raw.vcf.gz

    bcftools index \${chr}_filtered.vcf.gz

    # 6) Report post-filtering variant stats.
    bcftools stats \${chr}_filtered.vcf.gz > \${chr}_filtered.stats.txt
    printf "CHROM\\tPOS\\tID\\tMAF\\tHWE\\t%s\\n" "${info_field}" > \${chr}_filtered.variant_metrics.tsv
    bcftools query \
    -f "%CHROM\\t%POS\\t%ID\\t%INFO/MAF\\t%INFO/HWE\\t%INFO/${info_field}\\n" \
    \${chr}_filtered.vcf.gz >> \${chr}_filtered.variant_metrics.tsv

    # 7) Cleanup interim files.
    rm -f \${chr}_subset.bcf \${chr}_subset.bcf.csi \${chr}_subset.filled.bcf \${chr}_subset.filled.bcf.csi \${chr}_filtered.raw.vcf.gz \${chr}_filtered.raw.vcf.gz.csi

    """

}


workflow GENOTYPEQC {
    take:
        data
        fam
        plink
        plink2
        reference
        chain

    main:
        GenotypeQc_output_ch = GenotypeQC(
          data, 
          fam.ifEmpty { Channel.value(null) },
          plink.ifEmpty { Channel.value(null) }, 
          reference.ifEmpty { Channel.value(null) }, 
          chain.ifEmpty { Channel.value(null) }
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
      Covariate_PC_ch = RenderReport.out[1]
      Report_output_ch = RenderReport.out[2]

}

workflow CONVERTANDFILTERVCF {
    take:
      data

    main:
      VcfFilter_ch = ConvertAndFilterVcf(data)

    emit:
      VcfFilter_output_ch = VcfFilter_ch

}

workflow MERGEBED {
    take:
      data

    main:
      MergeBed_ch = MergeBed(data)

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