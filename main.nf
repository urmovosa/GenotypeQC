#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

def helpMessage() {
    log.info"""
    =======================================================
     GenoDataQC v${workflow.manifest.version}
    =======================================================
    Usage:
    The typical command for running the pipeline is as follows:
    nextflow run main.nf \
        --bfile EstBB_HT12v3\
        --gtp gte_EstBB_HT12v3.txt\
        --cohort_name EstBB_HT12v3\
        --genome_build GRCh37\
        --output_dir EstBB_HT12v3_GenoQc\
        -profile slurm\
        -resume

    Required arguments:
      --cohort_name                 Name of the cohort.
      --genome_build                Genome build of the cohort. Either hg18, GRCh36, hg19, GRCh37, hg38 or GRCh38.
      --bfile                       Path to unimputed genotype files in plink bed/bim/fam format (without extensions bed/bim/fam). Required if --vcf is not provided.
      --vcf                         Path to per-chromosome VCF input files. Required if --bfile is not provided.
      --fam                         Optional path to a plink fam file. This is especially helpful for sex annotation of samples in VCF files.
      --gtp                         Genotype-to-expression linking file. Tab-delimited, no header. First column: sample ID for genotype data. Can be used to filter samples from the analysis.
      --output_dir                  Path to the output directory.
      --qc_out_s                    "Outlierness" score threshold for excluding ethnic outliers. Defaults to 0.4 but it should be adjusted according to visual inspection.
      --qc_out_sd                   Threshold for declaring samples outliers based on genetic PC1 and PC2 SD from mean. Defaults to 3 and should be adjusted according to visual inspection.

    Optional arguments
      --inclusion_list              File with sample IDs to restrict to the analysis. Useful for keeping in the inclusion list of the samples. By default, all samples are kept.
      --exclusion_list              File with sample IDs to remove from the analysis. Useful for removing the ancestry outliers or restricting the genotype data to one superpopulation. Samples are also removed from the inclusion list. By default, all samples are kept.
      --additional_covariates       File with additional cohort-specific covariates. First column name SampleID is the sample ID. Following columns are named by covariates.  Categorical covariates need to be text-based (e.g. batch1, batch2, etc). 
      --preselected_sex_check_vars  Path to a plink ranges file that defines which variants to use for the check-sex command. Use this when the automatic selection does not yield satisfactory results.
      --snpfilter                   HapMap3 variant list. Defaults to the bundled list at $baseDir/data/hapmap3_snps.tsv.
      --plink_executable            Path to plink executable. By default this is automatically downloaded from internet, or bundled in the single_docker profile.
      --plink2_executable           Path to plink2 executable. By default this is automatically downloaded from internet, or bundled in the single_docker profile.
      --reference_1000g_folder      Path to 1000g reference folder. By default this is automatically downloaded from internet, or bundled in the single_docker profile.
      --chain_path                  Path to folder containing hg19ToHg38 and hg38ToHg19 chain files. By default these are automatically downloaded from internet, or bundled in the single_docker profile.
      --qc_hwe                      HWE p-value threshold for genotype QC (default: 1e-6).
      --qc_maf                      MAF threshold for genotype QC (default: 0.01).
      --vcf_maf                     MAF threshold for output VCF filtering (default: 0.01).
      --vcf_hwe                     HWE threshold for output VCF filtering (default: 1e-6).
      --vcf_imp                     Imputation quality threshold for output VCF filtering (default: 0.8).
      --vcf_imp_field               INFO sub-field code for storing imputation quality (default: R2).
      --vcf_genotype_field          INFO sub-field code indicating genotyped/typed variants (optional; e.g. typed or imputed).

    """.stripIndent()
}


// Define location of Report_template.Rmd
params.report_template = params.report_template ?: "$baseDir/bin/Report_template.Rmd"
params.embedded_runtime = params.embedded_runtime ?: false

if (params.embedded_runtime) {
  params.plink_executable = params.plink_executable ?: "$baseDir/.runtime/bin/plink"
  params.plink2_executable = params.plink2_executable ?: "$baseDir/.runtime/bin/plink2"
  params.reference_1000g_folder = params.reference_1000g_folder ?: "$baseDir/.runtime/reference_1000g"
  params.chain_path = params.chain_path ?: "$baseDir/.runtime/chain"
}

// Define set of accepted genome builds:
def genome_builds_accepted = ['hg18', 'GRCh36', 'hg19', 'GRCh37', 'hg38', 'GRCh38']

params.vcf = params.vcf ?: ''
params.bfile = params.bfile ?: ''
params.fam = params.fam ?: ''
params.snpfilter = params.snpfilter ?: "$baseDir/data/hapmap3_snps.tsv"

params.plink_executable = params.plink_executable ?: ''
params.plink2_executable = params.plink2_executable ?: ''
params.reference_1000g_folder = params.reference_1000g_folder ?: ''
params.chain_path = params.chain_path ?: ''

if (params.vcf != '') {

  Channel
      .fromPath("${params.vcf}/*.vcf.gz", checkIfExists: true)
      .ifEmpty { exit 1, "Input vcf files not found!" }
      .set { vcf_ch }

} else {

  Channel
    .from(params.bfile)
    .ifEmpty { exit 1, "Input plink prefix not found!" }
    .map { study -> [file("${study}.bed"), file("${study}.bim"), file("${study}.fam")]}
    .set { bfile_ch }

}

if (params.fam != '') {

  Channel
    .fromPath(params.fam, checkIfExists: true)
    .set { fam_annot_ch }

} else {

  Channel.empty()
    .set { fam_annot_ch }

}

Channel
    .fromPath(params.gtp)
    .ifEmpty { exit 1, "Input GTP file not found!" }
    .set { gtp_ch }

Channel
    .fromPath(params.report_template)
    .ifEmpty { exit 1, "Input report not found!" }
    .set { report_ch }

if (params.plink_executable) {
  Channel
    .fromPath(params.plink_executable)
    .ifEmpty('EMPTY')
    .set { plink_executable_ch }
} else {
  Channel.empty().set {plink_executable_ch}
}

if (params.plink2_executable) {
  Channel
    .fromPath(params.plink2_executable)
    .ifEmpty('EMPTY')
    .set { plink2_executable_ch }

  Channel
    .fromPath(params.plink2_executable)
    .ifEmpty('EMPTY')
    .map { it.toString() }
    .set { plink2_cmd_ch }
} else {
  Channel.empty().set {plink2_executable_ch}
  Channel.value('plink2').set { plink2_cmd_ch }
}
if (params.reference_1000g_folder) {
  Channel
    .fromPath(params.reference_1000g_folder)
    .ifEmpty('EMPTY')
    .set { reference_1000g_ch }
} else {
  Channel.empty().set {reference_1000g_ch}
}
if (params.chain_path) {
  Channel
    .fromPath(params.chain_path)
    .ifEmpty('EMPTY')
    .set { chain_path_ch }
} else {
  Channel.empty().set {chain_path_ch}
}

Channel
  .fromPath(params.snpfilter, checkIfExists: true)
  .set { snpfilter_ch }

params.qc_out_s = params.qc_out_s ?: 0.4
params.qc_out_sd = params.qc_out_sd ?: 3
params.cohort_name = params.cohort_name ?: ''
params.output_dir = params.output_dir ?: 'results'
params.genome_build = params.genome_build ?: 'hg19'

params.qc_hwe = params.qc_hwe ?: 1e-6
params.qc_maf = params.qc_maf ?: 0.01
params.vcf_maf = params.vcf_maf ?: 0.01
params.vcf_hwe = params.vcf_hwe ?: 1e-6
params.vcf_imp = params.vcf_imp ?: 0.8
params.vcf_imp_field = params.vcf_imp_field ?: 'R2'
params.vcf_genotype_field = params.vcf_genotype_field ?: ''

// By default define random non-colliding file names in data folder. If default, these are ignored by corresponding script.
params.inclusion_list = params.inclusion_list ?: "$baseDir/data/EmpiricalProbeMatching_AffyHumanExon.txt"
params.exclusion_list = params.exclusion_list ?: "$baseDir/data/EmpiricalProbeMatching_AffyU219.txt"
params.additional_covariates = params.additional_covariates ?: "$baseDir/data/1000G_pops.txt"

qc_out_s_ch = Channel.value(params.qc_out_s)
qc_out_sd_ch = Channel.value(params.qc_out_sd)
cohort_name_ch = Channel.value(params.cohort_name)
genome_build_ch = Channel.value(params.genome_build)

vcf_maf_ch = Channel.value(params.vcf_maf)
qc_hwe_ch = Channel.value(params.qc_hwe)
qc_maf_ch = Channel.value(params.qc_maf)
vcf_hwe_ch = Channel.value(params.vcf_hwe)
vcf_imp_ch = Channel.value(params.vcf_imp)
vcf_imp_field_ch = Channel.value(params.vcf_imp_field)
vcf_genotype_field_ch = Channel.value(params.vcf_genotype_field)

inclusion_list_ch = Channel.fromPath(params.inclusion_list, checkIfExists:true)
exclusion_list_ch = Channel.fromPath(params.exclusion_list, checkIfExists:true)
additional_covariates_ch = Channel.fromPath(params.additional_covariates, checkIfExists:true)

if ((params.genome_build in genome_builds_accepted) == false) {
  exit 1, "[Pipeline error] Genome build $params.genome_build not in accepted genome builds: $genome_builds_accepted \n"
}


// Header log info
log.info """=======================================================
GenoDataQC v${workflow.manifest.version}"
======================================================="""
def summary = [:]
summary['Pipeline Name']            = 'GenotypeDataQC'
summary['Pipeline Version']         = workflow.manifest.version
summary['PLINK bfile']              = params.bfile
summary['Genome Build']             = params.genome_build
summary['QC HWE threshold']         = params.qc_hwe
summary['QC MAF threshold']         = params.qc_maf
summary['VCF MAF threshold']        = params.vcf_maf
summary['VCF HWE threshold']        = params.vcf_hwe
summary['VCF INFO minimum']         = params.vcf_imp
summary['VCF INFO field']           = params.vcf_imp_field
summary['VCF genotype INFO field']  = params.vcf_genotype_field
summary['QC S threshold']           = params.qc_out_s
summary['QC SD threshold']          = params.qc_out_sd
summary['GTP file']                 = params.gtp
summary['SNP filter filter']        = params.snpfilter
summary['Max Memory']               = params.max_memory
summary['Max CPUs']                 = params.max_cpus
summary['Max Time']                 = params.max_time
summary['Cohort name']              = params.cohort_name
if(params.inclusion_list!="$baseDir/data/EmpiricalProbeMatching_AffyHumanExon.txt") summary['Inclusion list'] = params.inclusion_list
if(params.exclusion_list!="$baseDir/data/EmpiricalProbeMatching_AffyU219.txt") summary['Exclusion list'] = params.exclusion_list
summary['Plink executable']         = params.plink_executable
summary['Plink 2 executable']       = params.plink2_executable
summary['Reference 1000G folder']   = params.reference_1000g_folder
summary['Chain folder']             = params.chain_path
summary['Embedded runtime']         = params.embedded_runtime
summary['Output dir']               = params.output_dir
summary['Container Engine']         = workflow.containerEngine
if(workflow.containerEngine) summary['Container'] = workflow.container
summary['Current home']             = "$HOME"
summary['Current user']             = "$USER"
summary['Current path']             = "$PWD"
summary['Working dir']              = workflow.workDir
summary['Script dir']               = workflow.projectDir
summary['Config Profile']           = workflow.profile
log.info summary.collect { k,v -> "${k.padRight(21)}: $v" }.join("\n")
log.info "========================================="

include { GENOTYPEQC; GenotypeQC; RENDERREPORT; RenderReport; CONVERTANDFILTERVCF; ConvertAndFilterVcf; MERGEBED; MergeBed; FILTERFINALVCF; FilterFinalVcf} from './modules/GenotypeQc.nf'

workflow {

    if (params.vcf != '') {
      genotype_ch = vcf_ch
      .combine(qc_out_s_ch)
      .combine(qc_out_sd_ch)
      .combine(exclusion_list_ch)
      .combine(inclusion_list_ch)
      .combine(genome_build_ch)
      .combine(gtp_ch)
      .combine(snpfilter_ch)
      .combine(plink2_cmd_ch)
   
      CONVERTANDFILTERVCF(
        genotype_ch
        )

      merged_inputs_ch = CONVERTANDFILTERVCF.out
        .map { [it] }
        .collect()
        .map { list_of_tuples ->   // list_of_tuples = [[bed1,bim1,fam1], [bed2,bim2,fam2], ...]
        def beds = list_of_tuples.collect { it[0] }
        def bims = list_of_tuples.collect { it[1] }
        def fams = list_of_tuples.collect { it[2] }
        tuple(beds, bims, fams)
        }
        .combine(plink2_cmd_ch)

      MERGEBED(merged_inputs_ch)

      genotype_source_ch = MERGEBED.out
    } else {
      genotype_source_ch = bfile_ch
    }

  genotypeqc_input_ch = genotype_source_ch
      .combine(qc_out_s_ch)
      .combine(qc_out_sd_ch)
      .combine(qc_hwe_ch)
      .combine(qc_maf_ch)
      .combine(exclusion_list_ch)
      .combine(inclusion_list_ch)
      .combine(genome_build_ch)
      .combine(gtp_ch)
      .combine(snpfilter_ch)

  GENOTYPEQC(
      genotypeqc_input_ch, 
      fam_annot_ch, 
      plink_executable_ch, 
      plink2_executable_ch, 
      reference_1000g_ch, 
      chain_path_ch)

    if (params.vcf != '') {
      vcf_filter_input_ch = vcf_ch
      .combine(GENOTYPEQC.out[1])
      .combine(snpfilter_ch)
      .combine(vcf_maf_ch)
      .combine(vcf_hwe_ch)
      .combine(vcf_imp_ch)
      .combine(vcf_imp_field_ch)
      .combine(vcf_genotype_field_ch)

      FILTERFINALVCF(vcf_filter_input_ch)

      filter_vcf_output_files_ch = FILTERFINALVCF.out
      .map { it.flatten() }
      .collect()
      .map { it.flatten() }
    } else {
      filter_vcf_output_files_ch = Channel.value([])
    }

    report_input_ch = GENOTYPEQC.out[0]
    .combine(GENOTYPEQC.out[1])
    .combine(GENOTYPEQC.out[2])
    .combine(GENOTYPEQC.out[3])
    .combine(GENOTYPEQC.out[4])
    .combine(qc_out_s_ch)
    .combine(qc_out_sd_ch)
    .combine(report_ch)
    .combine(additional_covariates_ch)
    .combine(filter_vcf_output_files_ch)
    .combine(vcf_genotype_field_ch)

    RENDERREPORT(report_input_ch) 

}