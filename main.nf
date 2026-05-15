#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

def helpMessage() {
    log.info"""
    =======================================================
  GenotypeQC v${workflow.manifest.version}
    =======================================================
    Usage:
    The typical command for running the pipeline is as follows:
    nextflow run main.nf \
        --bfile cohort_a\
        --cohort_name cohort_a\
        --genome_build GRCh37\
        --output_dir results/cohort_a\
        -profile slurm\
        -resume

    Required arguments:
      --cohort_name                 Name of the cohort.
      --genome_build                Genome build of the cohort. Either hg18, GRCh36, hg19, GRCh37, hg38 or GRCh38.
      --bfile                       Path to unimputed genotype files in plink bed/bim/fam format (without extensions bed/bim/fam). Required if --vcf is not provided.
      --vcf                         Path to per-chromosome VCF input files. Required if --bfile is not provided.
      --fam                         Optional path to a plink fam file. This is especially helpful for sex annotation of samples in VCF files.
      --output_dir                  Path to the output directory.
      --qc_out_s                    "Outlierness" score threshold for excluding ethnic outliers. Defaults to 0.4 but it should be adjusted according to visual inspection.
      --qc_out_sd                   Threshold for declaring samples outliers based on genetic PC1 and PC2 SD from mean. Defaults to 3 and should be adjusted according to visual inspection.

    Optional arguments
      --inclusion_list              File with sample IDs to restrict to the analysis. Useful for keeping only a subset of samples. By default, all samples are kept.
      --exclusion_list              File with sample IDs to remove from the analysis. Useful for removing ancestry outliers or restricting the genotype data to one superpopulation. Samples are also removed from the inclusion list. By default, no samples are removed.
      --additional_covariates       File with additional cohort-specific covariates. First column name SampleID is the sample ID. Following columns are named by covariates. Categorical covariates need to be text-based (e.g. batch1, batch2, etc). By default, no extra covariates are added.
      --preselected_sex_check_vars  Path to a plink ranges file that defines which variants to use for the check-sex command. Use this when the automatic selection does not yield satisfactory results.
      --snpfilter                   HapMap3 variant list. Defaults to the bundled list at $baseDir/data/hapmap3_snps.tsv.
      --reference_unrelated_samples File with unrelated 1000G reference sample indices. Defaults to the bundled file at $baseDir/data/unrelated_reference_samples_ids.txt.
      --reference_populations       File with 1000G sample population labels. Defaults to the bundled file at $baseDir/data/1000G_pops.txt.
      --plink_executable            Path to a PLINK-compatible executable. Defaults to the cached PLINK 2 binary in $baseDir/.runtime_downloads/bin/.
      --plink2_executable           Path to plink2 executable. Defaults to $baseDir/.runtime_downloads/bin/plink2 for host runs, or the bundled binary in single_docker.
      --reference_1000g_folder      Path to 1000g reference folder. Defaults to $baseDir/.runtime_downloads/reference_1000g for host runs, or the bundled reference in single_docker.
      --chain_path                  Path to folder containing hg19ToHg38 and hg38ToHg19 chain files. Defaults to $baseDir/.runtime_downloads/chain for host runs, or the bundled files in single_docker.
      --liftover_executable         Path to the UCSC liftOver executable. Defaults to $baseDir/.runtime_downloads/bin/liftOver for host runs, or the bundled binary in single_docker.
      --runtime_cache_dir           Host-side cache used for auto-downloaded runtime assets (default: $baseDir/.runtime_downloads).
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
params.runtime_cache_dir = params.runtime_cache_dir ?: "$baseDir/.runtime_downloads"

if (params.embedded_runtime) {
  params.liftover_executable = params.liftover_executable ?: "$baseDir/.runtime/bin/liftOver"
  params.plink_executable = params.plink_executable ?: "$baseDir/.runtime/bin/plink"
  params.plink2_executable = params.plink2_executable ?: "$baseDir/.runtime/bin/plink2"
  params.reference_1000g_folder = params.reference_1000g_folder ?: "$baseDir/.runtime/reference_1000g"
  params.chain_path = params.chain_path ?: "$baseDir/.runtime/chain"
} else {
  params.plink2_executable = params.plink2_executable ?: "${params.runtime_cache_dir}/bin/plink2"
  params.plink_executable = params.plink_executable ?: params.plink2_executable
  params.reference_1000g_folder = params.reference_1000g_folder ?: "${params.runtime_cache_dir}/reference_1000g"
  params.chain_path = params.chain_path ?: "${params.runtime_cache_dir}/chain"
  params.liftover_executable = params.liftover_executable ?: "${params.runtime_cache_dir}/bin/liftOver"
}

def resolved_plink_executable = params.plink_executable ?: (params.embedded_runtime ? "$baseDir/.runtime/bin/plink" : "${params.runtime_cache_dir}/bin/plink2")
def resolved_plink2_executable = params.plink2_executable ?: (params.embedded_runtime ? "$baseDir/.runtime/bin/plink2" : "${params.runtime_cache_dir}/bin/plink2")
def resolved_reference_1000g_folder = params.reference_1000g_folder ?: (params.embedded_runtime ? "$baseDir/.runtime/reference_1000g" : "${params.runtime_cache_dir}/reference_1000g")
def resolved_chain_path = params.chain_path ?: (params.embedded_runtime ? "$baseDir/.runtime/chain" : "${params.runtime_cache_dir}/chain")
def resolved_liftover_executable = params.liftover_executable ?: (params.embedded_runtime ? "$baseDir/.runtime/bin/liftOver" : "${params.runtime_cache_dir}/bin/liftOver")
def resolved_runtime_asset_root = params.embedded_runtime ? "$baseDir/.runtime" : params.runtime_cache_dir

// Define set of accepted genome builds:
def genome_builds_accepted = ['hg18', 'GRCh36', 'hg19', 'GRCh37', 'hg38', 'GRCh38']

params.vcf = params.vcf ?: ''
params.bfile = params.bfile ?: ''
params.fam = params.fam ?: ''
params.snpfilter = params.snpfilter ?: "$baseDir/data/hapmap3_snps.tsv"
params.reference_unrelated_samples = params.reference_unrelated_samples ?: "$baseDir/data/unrelated_reference_samples_ids.txt"
params.reference_populations = params.reference_populations ?: "$baseDir/data/1000G_pops.txt"

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
  Channel.value(params.fam).set { fam_annot_ch }
} else {
  Channel.value(params.fam).set { fam_annot_ch }
}

Channel
    .fromPath(params.report_template)
    .ifEmpty { exit 1, "Input report not found!" }
    .set { report_ch }

Channel.value(resolved_plink_executable).set { plink_executable_ch }
Channel.value(resolved_plink2_executable).set { plink2_executable_ch }
Channel.value(resolved_plink2_executable).set { plink2_cmd_ch }
Channel.value(resolved_reference_1000g_folder).set { reference_1000g_ch }
Channel.value(resolved_chain_path).set { chain_path_ch }
Channel.value(resolved_runtime_asset_root).set { runtime_asset_root_ch }

Channel
  .fromPath(params.snpfilter, checkIfExists: true)
  .set { snpfilter_ch }

Channel
  .fromPath(params.reference_unrelated_samples, checkIfExists: true)
  .set { reference_unrelated_samples_ch }

Channel
  .fromPath(params.reference_populations, checkIfExists: true)
  .set { reference_populations_ch }

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

params.inclusion_list = params.inclusion_list ?: ''
params.exclusion_list = params.exclusion_list ?: ''
params.additional_covariates = params.additional_covariates ?: ''

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

inclusion_list_ch = Channel.value(params.inclusion_list)
exclusion_list_ch = Channel.value(params.exclusion_list)
additional_covariates_ch = Channel.value(params.additional_covariates)

if ((params.genome_build in genome_builds_accepted) == false) {
  exit 1, "[Pipeline error] Genome build $params.genome_build not in accepted genome builds: $genome_builds_accepted \n"
}


// Header log info
log.info """=======================================================
GenotypeQC v${workflow.manifest.version}"
======================================================="""
def summary = [:]
summary['Pipeline Name']            = 'GenotypeQC'
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
summary['SNP filter filter']        = params.snpfilter
summary['Max Memory']               = params.max_memory
summary['Max CPUs']                 = params.max_cpus
summary['Max Time']                 = params.max_time
summary['Cohort name']              = params.cohort_name
if(params.inclusion_list) summary['Inclusion list'] = params.inclusion_list
if(params.exclusion_list) summary['Exclusion list'] = params.exclusion_list
if(params.additional_covariates) summary['Additional covariates'] = params.additional_covariates
summary['Plink executable']         = resolved_plink_executable
summary['Plink 2 executable']       = resolved_plink2_executable
summary['Reference 1000G folder']   = resolved_reference_1000g_folder
summary['Reference sample index']   = params.reference_unrelated_samples
summary['Reference populations']    = params.reference_populations
summary['Chain folder']             = resolved_chain_path
summary['LiftOver executable']      = resolved_liftover_executable
summary['Runtime cache']            = params.runtime_cache_dir
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

include { PREPARERUNTIMEASSETS; PrepareRuntimeAssets; GENOTYPEQC; GenotypeQC; RENDERREPORT; RenderReport; CONVERTANDFILTERVCF; ConvertAndFilterVcf; MERGEBED; MergeBed; FILTERFINALVCF; FilterFinalVcf} from './modules/GenotypeQc.nf'

workflow {

  PREPARERUNTIMEASSETS(runtime_asset_root_ch)
  runtime_ready_ch = PREPARERUNTIMEASSETS.out

    if (params.vcf != '') {
      genotype_ch = vcf_ch
      .combine(qc_out_s_ch)
      .combine(qc_out_sd_ch)
      .combine(exclusion_list_ch)
      .combine(inclusion_list_ch)
      .combine(genome_build_ch)
      .combine(snpfilter_ch)
      .combine(plink2_cmd_ch)
   
      CONVERTANDFILTERVCF(
        genotype_ch,
        runtime_ready_ch
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

      MERGEBED(merged_inputs_ch, runtime_ready_ch)

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
      .combine(snpfilter_ch)

  GENOTYPEQC(
      genotypeqc_input_ch, 
      runtime_ready_ch,
      fam_annot_ch, 
      plink_executable_ch, 
      plink2_executable_ch, 
      reference_1000g_ch, 
      chain_path_ch,
      reference_unrelated_samples_ch,
      reference_populations_ch)

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
      .map { list_of_outputs -> tuple(list_of_outputs.flatten()) }
    } else {
      filter_vcf_output_files_ch = Channel.value(tuple([]))
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
    .map { row ->
      def items = row instanceof List ? row : [row]
      def fixed_inputs = items.take(9)
      def vcf_filter_outputs = items.size() > 10 ? items[9..-2] : []
      def genotype_field = items[-1]
      tuple(
        fixed_inputs[0],
        fixed_inputs[1],
        fixed_inputs[2],
        fixed_inputs[3],
        fixed_inputs[4],
        fixed_inputs[5],
        fixed_inputs[6],
        fixed_inputs[7],
        fixed_inputs[8],
        vcf_filter_outputs,
        genotype_field
      )
    }

    RENDERREPORT(report_input_ch) 

}