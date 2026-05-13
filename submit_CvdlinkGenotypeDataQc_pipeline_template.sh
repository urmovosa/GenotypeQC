#!/bin/bash

#SBATCH --time=48:00:00
#SBATCH -N 1
#SBATCH --ntasks-per-node=1
#SBATCH --mem=6G
#SBATCH --mail-type=BEGIN
#SBATCH --mail-type=END
#SBATCH --mail-type=FAIL
#SBATCH --job-name="DataQc"

# These are needed modules in UT HPC to get singularity and Nextflow running. Replace with appropriate ones for your HPC.
module load openjdk/17.0.3_7
module load singularity/3.8.5
module load squashfs/4.4

# We set the following variables for nextflow to prevent writing to your home directory (and potentially filling it completely)
# Feel free to change these as you wish.
export SINGULARITY_CACHEDIR=../../singularitycache
export NXF_HOME=../../nextflowcache

# Disable pathname expansion. Nextflow handles pathname expansion by itself.
set -f

# Define paths
nextflow_path=[Nextflow path] # folder where Nextflow executable is
plink_path=[PLINK path] # folder where PLINK executable is

# Genotype data
vcf_path=["Path to input .vcf files"]

# HapMap variant list
hapmap3=[File with HapMap SNP IDs]

# Other data
cohort_name=["Your dataset name"]
genome_build=[Genome build, e.g. "GRCh38"]
output_path=../output # Output path

# Additional settings and optional arguments for the command

# --qc_out_s [numeric threshold]
# --qc_out_sd [numeric threshold]
# --qc_hwe [HWE p-value threshold for genotype QC]
# --qc_maf [MAF threshold for genotype QC]
# --vcf_maf [MAF threshold for final VCF filtering]
# --vcf_hwe [HWE p-value threshold for final VCF filtering]
# --vcf_imp [minimum imputation quality for final VCF filtering]
# --inclusion_list [file with the list of samples to restrict the analysis]
# --exclusion_list [file with the list of samples to remove from the analysis]
# --additional_covariates [file with additional covariates. First column should be `SampleID`]
# --fam [PLINK .fam file.]
# --plink_executable [path to plink executable (PLINK v1.90b6.26 64-bit)]
# --plink2_executable [path to plink2 executable (PLINK v2.00a3.7LM 64-bit Intel)]
# --reference_1000g_folder [path to folder with 1000G reference data]
# --chain_path [folder with hg19->hg38 and hg38->hg19 chain files]
# --vcf_imp_field [INFO sub-field storing imputation quality metric (default R2)]
# --vcf_genotype_field [optional INFO sub-field indicating typed/genotyped vs imputed status]

# Command:
NXF_VER=25.09.2-edge ${nextflow_path}/nextflow run main.nf \
--vcf ${vcf_path} \
--snpfilter ${hapmap3} \
--cohort_name ${cohort_name} \
--genome_build ${genome_build} \
--output_dir ${output_path}  \
--plink2_executable ${plink_path}/plink2 \
-profile slurm,singularity \
-resume
