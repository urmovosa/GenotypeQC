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

# Genotype data
vcf_path=["Path to input .vcf files"]

# GTP file
gtp=[File with genotype IDs]

# HapMap variant list
hapmap3=[File with HapMap SNP IDs]

# Other data
cohort_name=["Your dataset name"]
genome_build=[Genome build, e.g. "GRCh38"]
output_path=../output # Output path

# Additional settings and optional arguments for the command

# --GenOutThresh [numeric threshold]
# --GenSdThresh [numeric threshold]
# --InclusionList [file with the list of samples to restrict the analysis]
# --ExclusionList [file with the list of samples to remove from the analysis]
# --AdditionalCovariates [file with additional covariates. First column should be `SampleID`]
# --fam [PLINK .fam file.]
# --plink_executable [path to plink executable (PLINK v1.90b6.26 64-bit)]
# --plink2_executable [path to plink2 executable (PLINK v2.00a3.7LM 64-bit Intel)]
# --reference_1000g_folder [path to folder with 1000G reference data]
# --chain_path [folder with hg19->hg38 and hg38->hg19 chain files]

# Command:
NXF_VER=25.09.2-edge ${nextflow_path}/nextflow run main.nf \
--vcf ${vcf_path} \
--snpfilter ${hapmap3} \
--cohort_name ${cohort_name} \
--genome_build ${genome_build} \
--gtp ${gtp} \
--outputDir ${output_path}  \
--plink2_executable /gpfs/space/GI/GV/Projects/eQTLGenPhase2/temp_fix_offline_files/input/eQTLGenP2OfflineFiles/1_DataQC_additional_files/plink_executables/plink2 \
-profile slurm,singularity \
-resume
