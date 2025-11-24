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
      tuple path(bfile), path(bim), path(fam), val(s_stat), val(sd_thresh), path(ExclusionList), \
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

    publishDir "${params.outputDir}", mode: 'copy', overwrite: true

    input:
      tuple path(output_gen), path(fam), path(ref_af), path(target_af), path(sexcheck), val(stresh), val(sdtresh), path(report), path(additional_covariates)

    output:
      path ('outputfolder_gen/')
      path ('Report_DataQc*')
      path ('CovariatePCs.txt')

    script:
    """
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

    input:
      tuple path(vcf), path(filtered_fam), path(snplist), val(maf), val(imputation_th)

    output:
      path("*_filtered.vcf.gz")

    script:
    """
    chr=\$(basename ${vcf} | grep -oE '^chr[0-9XYM]+')
    zcat ${snplist} | cut -f1 | tail -n +2 > hapmap3_snplist.txt

    awk 'NR>1 {print \$2}' ${filtered_fam} > iids.txt

    # MAF and INFO/R2 fields can vary in vcf.gz
    # TODO: 
    # filter first by samples
    # Then recalculate MAF, HWE and imputation quality score
    # Then calculate per-chr statistics
    # Then report per-snp maf, hwe and imputation summaries
    # Then apply SNP filters
    # Then delete interim files
    # Then calculate per-chr statistics
    bcftools view \
    -S iids.txt \
    -i 'MAF>=0.01 && INFO/R2>=0.8' \
    -Oz -o \${chr}_filtered.vcf.gz \
    ${vcf}

    bcftools index \${chr}_filtered.vcf.gz

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