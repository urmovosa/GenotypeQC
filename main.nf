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
        --genome_build GRCh37
        --outdir EstBB_HT12v3_GenoQc\
        -profile slurm\
        -resume

    Mandatory arguments:
      --cohort_name                 Name of the cohort.
      --genome_build                Genome build of the cohort. Either hg18, GRCh36, hg19, GRCh37, hg38 or GRCh38.
      --bfile                       Path to unimputed genotype files in plink bed/bim/fam format (without extensions bed/bim/fam).
      --vcf                         Path to a vcf file.
      --fam                         Path to a plink fam file. This is especially helpful for sex annotation of samples in VCF files.
      --snpfilter                   Gzipped file with HapMap3 variants.
      --gtp                         Genotype file. Tab-delimited, no header. First column: sample ID for genotype data. Can be used to filter samples from the analysis.
      --outputDir                   Path to the output directory.
      --GenOutThresh                "Outlierness" score threshold for excluding ethnic outliers. Defaults to 0.4 but it should be adjusted according to visual inspection.
      --GenSdThresh                 Threshold for declaring samples outliers based on genetic PC1 and PC2. Defaults to 3 SD from the mean of PC1 and PC2 but should be adjusted according to visual inspection.
      --gen_qc_steps                Either generic, array-based, QC or including also WGS specific QC (only valid with VCF datasets). 'Array' (default) or 'WGS' (Generic + WGS qc).

    Optional arguments
      --InclusionList               File with sample IDs to restrict to the analysis. Useful for keeping in the inclusion list of the samples. By default, all samples are kept.
      --ExclusionList               File with sample IDs to remove from the analysis. Useful for removing the ancestry outliers or restricting the genotype data to one superpopulation. Samples are also removed from the inclusion list. By default, all samples are kept.
      --AdditionalCovariates        File with additional cohort-specific covariates. First column name SampleID is the sample ID. Following columns are named by covariates.  Categorical covariates need to be text-based (e.g. batch1, batch2, etc). 
      --preselected_sex_check_vars  Path to a plink ranges file that defines which variants to use for the check-sex command. Use this when the automatic selection does not yield satisfactory results.
      --plink_executable            Path to plink executable. By default this is automatically downloaded from internet. Use this setting when you have to work offline.
      --plink2_executable           Path to plink2 executable. By default this is automatically downloaded from internet. Use this setting when you have to work offline.
      --reference_1000g_folder      Path to 1000g reference folder. By default this is automatically downloaded from internet. Use this setting when you have to work offline.
      --chain_path                  Path to folder containing hg19ToHg38 and hg38ToHg19 chain files. By default these are automatically downloaded from internet. Use this setting when you have to work offline and your build is hg38.
      --imputation_info_field       INFO sub-field code that stores imputation quality (default: R2).

    """.stripIndent()
}


// Define location of Report_template.Rmd
params.report_template = "$baseDir/bin/Report_template.Rmd"

// Define set of accepted genome builds:
def genome_builds_accepted = ['hg18', 'GRCh36', 'hg19', 'GRCh37', 'hg38', 'GRCh38']
def genotyping_platforms_accepted = ['Array', 'WGS']

params.vcf = ''
params.bfile = ''
params.fam = ''
params.snpfilter = ''

params.plink_executable = ''
params.plink2_executable = ''
params.reference_1000g_folder = ''
params.chain_path = ''

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
} else {
  Channel.empty().set {plink2_executable_ch}
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

params.GenOutThresh = 0.4
params.GenSdThresh = 3
params.cohort_name = ''
params.outputDir = 'results'
params.genome_build = 'hg19'
params.gen_qc_steps = "Array"

params.maf_threshold = 0.01
params.imputation_quality_threshold = 0.8
params.imputation_info_field = 'R2'

// By default define random non-colliding file names in data folder. If default, these are ignored by corresponding script.
params.InclusionList = "$baseDir/data/EmpiricalProbeMatching_AffyHumanExon.txt"
params.ExclusionList = "$baseDir/data/EmpiricalProbeMatching_AffyU219.txt"
params.AdditionalCovariates = "$baseDir/data/1000G_pops.txt"

GenOutThresh_ch = Channel.value(params.GenOutThresh)
GenSdThresh_ch = Channel.value(params.GenSdThresh)
cohort_name_ch = Channel.value(params.cohort_name)
genome_build_ch = Channel.value(params.genome_build)

maf_ch = Channel.value(params.maf_threshold)
imputation_quality_ch = Channel.value(params.imputation_quality_threshold)
imputation_info_field_ch = Channel.value(params.imputation_info_field)

InclusionList_ch = Channel.fromPath(params.InclusionList, checkIfExists:true)
ExclusionList_ch = Channel.fromPath(params.ExclusionList, checkIfExists:true)
AdditionalCovariates_ch = Channel.fromPath(params.AdditionalCovariates, checkIfExists:true)

if ((params.gen_qc_steps in genotyping_platforms_accepted) == false) {
  exit 1, "[Pipeline error] Genotype QC steps $params.gen_qc_steps not one of: $genotyping_platforms_accepted \n"
}

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
summary['Gen QC steps']             = params.gen_qc_steps
summary['Genome Build']             = params.genome_build
summary['MAF filter']               = params.maf_threshold
summary['Imputation filter']        = params.imputation_quality_threshold
summary['Imputation INFO code']     = params.imputation_info_field
summary['S threshold']              = params.GenOutThresh
summary['Gen SD threshold']         = params.GenSdThresh
summary['GTP file']                 = params.gtp
summary['SNP filter filter']        = params.snpfilter
summary['Max Memory']               = params.max_memory
summary['Max CPUs']                 = params.max_cpus
summary['Max Time']                 = params.max_time
summary['Cohort name']              = params.cohort_name
if(params.InclusionList!="$baseDir/data/EmpiricalProbeMatching_AffyHumanExon.txt") summary['Inclusion list'] = params.InclusionList
if(params.ExclusionList!="$baseDir/data/EmpiricalProbeMatching_AffyHumanExon.txt") summary['Exclusion list'] = params.ExclusionList
summary['Expression platform']      = params.exp_platform
summary['Plink executable']         = params.plink_executable
summary['Plink 2 executable']       = params.plink2_executable
summary['Reference 1000G folder']   = params.reference_1000g_folder
summary['Chain folder']             = params.chain_path
summary['Output dir']               = params.outputDir
summary['Working dir']              = workflow.workDir
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
      .combine(GenOutThresh_ch)
      .combine(GenSdThresh_ch)
      .combine(ExclusionList_ch)
      .combine(InclusionList_ch)
      .combine(genome_build_ch)
      .combine(gtp_ch)
      .combine(snpfilter_ch)
      .combine(plink2_executable_ch)
    } else {
      genotype_ch = bfile_ch
      .combine(GenOutThresh_ch)
      .combine(GenSdThresh_ch)
      .combine(ExclusionList_ch)
      .combine(InclusionList_ch)
      .combine(genome_build_ch)
      .combine(gtp_ch)
      .combine(snpfilter_ch)
      .combine(plink2_executable_ch)
    }
   
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

  MERGEBED(merged_inputs_ch)

  genotypeqc_input_ch = MERGEBED.out
      .combine(GenOutThresh_ch)
      .combine(GenSdThresh_ch)
      .combine(ExclusionList_ch)
      .combine(InclusionList_ch)
      .combine(genome_build_ch)
      .combine(gtp_ch)
      .combine(snpfilter_ch)
      .combine(plink2_executable_ch)

  GENOTYPEQC(
      genotypeqc_input_ch, 
      fam_annot_ch, 
      plink_executable_ch, 
      plink2_executable_ch, 
      reference_1000g_ch, 
      chain_path_ch)

    vcf_filter_input_ch = vcf_ch
    .combine(GENOTYPEQC.out[1])
    .combine(snpfilter_ch)
    .combine(maf_ch)
    .combine(imputation_quality_ch)
    .combine(imputation_info_field_ch)

    FILTERFINALVCF(vcf_filter_input_ch)

    filter_vcf_output_files_ch = FILTERFINALVCF.out
    .map { it.flatten() }
    .collect()
    .map { it.flatten() }

    report_input_ch = GENOTYPEQC.out[0]
    .combine(GENOTYPEQC.out[1])
    .combine(GENOTYPEQC.out[2])
    .combine(GENOTYPEQC.out[3])
    .combine(GENOTYPEQC.out[4])
    .combine(GenOutThresh_ch)
    .combine(GenSdThresh_ch)
    .combine(report_ch)
    .combine(AdditionalCovariates_ch)
    .combine(filter_vcf_output_files_ch)

    report_input_ch.view()

    RENDERREPORT(report_input_ch) 

}