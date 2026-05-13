# CVDLINK genotype QC pipeline

Automatic data quality check and processing for genotype data in .vcf format (or PLINK bed/bim/fam input).

Performs the following main steps:

- Genotypes
  - Standard variant QC filtering for the subset HapMap3 variants (call-rate>0.95, Hardy-Weinberg P>1e-6, MAF>0.01).
  - Individual-level missingness filter <0.05.
  - Comparison of reported and genetic check, removal of mismatched samples.
  - Removal of samples with unclear genetic sex.
  - Removal of samples with excess heterozygosity (+/-3SD from the mean).
  - Removal of related samples (3d degree relatives). From each pair of related samples, one is kept in the data.
  - Visualisation of samples in the genetic reference space, instructions how to remove or split the data in case of multi-ancestry samples.
  - Removal of in-sample genetic outliers.
  - Calculates 10 first genetic principal components (PCs), used in analyses as covariates to correct for population stratification
  - Filters full imputed dataset to exclude samples and variants failing QC (adjustable filters for Hardy-Weinberg P, MAF and imputation quality) when VCF input is provided. 
- Additional steps:
  - Reorders the genotype samples into random order.
  - Organises all the QCd data into the standard folder format.
  - Provides commented `html` QC report which should be used to get an overview of the quality of the data.

## Usage information

### Requirements for the system

- Have access to HPC or workstation (preferably with multiple cores).
- For host or scheduler runs: have Bash >=3.2, Java >=17, Nextflow, and either Singularity/Apptainer or Docker available.
- For the bundled single-image run: only Docker is required on the host.

### Setup of the pipeline

You can either clone it by using git (if available in HPC):

`git clone https://github.com/urmovosa/GenotypeQC.git`

Or just download this from the gitlab/github download link and unzip.

### Single Docker image

The repo now ships a self-contained Docker build for local execution. The image includes Java, Nextflow, the R/conda runtime, PLINK 1.9, PLINK 2, the 1000G reference, and the hg19<->hg38 liftOver chain files. In this mode you only need to mount your study input files and a writable workspace.

Build the image:

```bash
docker buildx build --platform linux/amd64 --load -t genotypeqc:latest .
```

Run with per-chromosome VCF input. The image entrypoint injects `-profile single_docker` automatically:

```bash
docker run --rm -it \
  --platform linux/amd64 \
  -v "$PWD:/workspace" \
  -v /absolute/path/to/input:/input:ro \
  genotypeqc:latest \
  --vcf /input/imputed_vcfs \
  --cohort_name EstBB_HT12v3 \
  --genome_build GRCh38 \
  --output_dir /workspace/results \
  -resume
```

Run with PLINK bed/bim/fam input:

```bash
docker run --rm -it \
  --platform linux/amd64 \
  -v "$PWD:/workspace" \
  -v /absolute/path/to/input:/input:ro \
  genotypeqc:latest \
  --bfile /input/study_prefix \
  --cohort_name EstBB_HT12v3 \
  --genome_build GRCh37 \
  --output_dir /workspace/results \
  -resume
```

Notes:

- Mount a writable directory at `/workspace` so Nextflow can keep `work/`, `.nextflow/`, and output files between runs.
- The bundled PLINK binaries are `x86_64`, so build and run the image as `linux/amd64` on Apple Silicon hosts. Use `docker buildx` for the image build.
- `--plink_executable`, `--plink2_executable`, `--reference_1000g_folder`, and `--chain_path` are optional in this mode because the image already bundles them.
- `--snpfilter` is also optional unless you want to override the bundled HapMap3 list.

### Input files

- Per-chromosome genotype files in `.vcf` format (or PLINK bed/bim/fam prefix via `--bfile`). Genome build has to be in **hg18/GRCh36**, **hg19/GRCh37 (default)** or **hg38/GRCh38**. Pathname extension using globbing is allowed (using `*` or `?`), but the path should be provided without pathway extension.
- It is advisable to supply a `.fam` file that also includes observed sex for all samples (format: males=1, females=2), so the pipeline does an extra check on that. However, if this information is not available for all samples, the pipeline skips this check.

### Required inputs

`--cohort_name`                 Name of the cohort.

`--vcf`                         Path to the imputed genotype files in `vcf` format (glob allowed). Required if `--bfile` is not provided.

`--bfile`                       Path prefix to unimputed genotype files in PLINK bed/bim/fam format (without extensions). Required if `--vcf` is not provided.

`--genome_build`                Genome build of the cohort. Either hg18, GRCh36, hg19, GRCh37, hg38 or GRCh38. Defaults to hg19.

`--output_dir`                  Path to the output directory. Defaults to `results`.
    
### Additional settings

There are some arguments which can be used to adjust certain outlier detection thresholds. These should be adjusted after initial run with the default settings and after investigating the diagnostic plots in the `Report_DataQc_[cohort name].html`. Then the pipeline should be re-run with adjusted settings.

`--qc_out_s` Threshold for declaring genotype sample genetic outlier, based on LOF "outlierness" metric. Default is 0.4.

`--qc_out_sd` Threshold for declaring genotype sample genetic outlier, based on the deviation from the means of first two genetic PCs. Defaults to 3 SD from the mean.

`--qc_hwe` HWE p-value threshold for genotype QC filtering (default `1e-6`).

`--qc_maf` MAF threshold for genotype QC filtering (default `0.01`).

`--vcf_maf` MAF threshold for final VCF filtering (default `0.01`).

`--vcf_hwe` HWE p-value threshold for final VCF filtering (default `1e-6`).

`--vcf_imp` Minimum imputation quality threshold for final VCF filtering (default `0.8`).

Optional arguments:

`--additional_covariates` Tab-separated file with additional external covariates relevant for downstream genotype-based analyses in the dataset. First column must have header "SampleID" and following columns must include corresponding covariates with informative headers (E.g. "GenotypeBatch", etc.). Categorical covariates must be specified in the text format (E.g. "Batch1", "Batch2", "Batch3"), not encoded as numbers. Pipeline does one-hot encoding for you. Numerical covariates are allowed as well. If specified, this file should include covariate information for each QC-passed sample and NAs are not allowed. 

`--inclusion_list` File with the genotype IDs to keep in the analysis (one per row). Useful for e.g. keeping in only the samples which have part of the biobank, etc. By default, pipeline keeps all samples in. No header needed.

`--exclusion_list` File with the genotype IDs to remove from the analysis (one per row). Useful for removing part of the samples from the analysis if these are from different ancestry. In case of the overlap between inclusion list and exclusion list, intersect is kept in the analysis. No header needed.

`--fam` PLINK .fam file. Useful for specifying known sex of the samples.

`--snpfilter` HapMap3 variant list. Defaults to the bundled `data/hapmap3_snps.tsv`.

`--plink_executable`    Path to plink executable. By default this is automatically downloaded from internet for host runs, or bundled in the `single_docker` profile.

`--plink2_executable`   Path to plink2 executable. By default this is automatically downloaded from internet for host runs, or bundled in the `single_docker` profile.

`--reference_1000g_folder`  Path to 1000g reference folder. By default this is automatically downloaded from internet for host runs, or bundled in the `single_docker` profile.

`--chain_path` Path to folder containing hg19ToHg38 and hg38ToHg19 chain files (only needed for hg38/GRCh38). These are bundled in the `single_docker` profile.

`--vcf_imp_field` INFO sub-field that stores the imputation quality metric (default `R2`).

`--vcf_genotype_field` Optional INFO sub-field that indicates genotyped/typed versus imputed variants (examples: `typed`, `imputed`).

### Offline / isolated run

See the offline usage instructions and helper script:

- [docs/OFFLINE.md](docs/OFFLINE.md)
- [scripts/offline_fetch.sh](scripts/offline_fetch.sh)

Note: for offline runs, provide local paths for `--plink_executable`, `--plink2_executable`, `--reference_1000g_folder`, and `--chain_path` when needed.

If you use the bundled Docker image above, those assets are already included in the image and this extra setup is not needed.

### Running the data QC command

Modify the Slurm script template `submit_CvdlinkGenotypeDataQc_pipeline_template.sh` with your input paths. Below is an example template for Slurm scheduler.

```bash
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
--plink2_executable /gpfs/space/GI/GV/Projects/eQTLGenPhase2/temp_fix_offline_files/input/eQTLGenP2OfflineFiles/1_DataQC_additional_files/plink_executables/plink2 \
-profile slurm,singularity \
-resume
```

You can save the modified script version to informative name, e.g. `submit_CvdlinkGenotypeDataQc_[**CohortName**].sh`.

You can select HPC scheduler type by adjusting the profile as following:

- Slurm: `-profile slurm,singularity`
- PBS/TORQUE: `-profile pbs,singularity`
- SGE: `-profile sge,singularity`

If you are working on the single node you can also run the pipeline without scheduler by using `-profile local_vm,singularity`

Then submit the job `sbatch submit_CvdlinkGenotypeDataQc_[**CohortName**].sh`. This initiates pipeline, makes analysis environment (using singularity) and automatically submits the steps in correct order and parallel way. Separate `work` directory is made to the folder and contains all interim files.

### Monitoring and debugging

- Monitoring:
  - Monitor the `slurm-***.out` log file and check if all the steps finish without error. Trick: command `watch tail -n 20 slurm-***.out` helps you to interactively monitor the status of the jobs.
  - Use `squeue -u [YourUserName]` to see if individual tasks are in the queue.
- If the pipeline crashes (e.g. due to walltime), you can just resubmit the same script after the fixes. Nextflow does not rerun completed steps and continues only from the steps which had not completed.
- When the work has finished, download and check the job report. This file is automatically written to your output folder `pipeline_info` subfolder, for potential errors or warnings. E.g. `output/pipeline_info/Cvdlink_GenotypeQc_report.html`.
- When you need to do some debugging, then you can use the last section of aforementioned report to figure out in which subfolder from `work` folder the actual step was run. You can then navigate to this folder and investigate the following hidden files:
  - `.command.sh`: script which was submitted.
  - `.command.log`: log file for seeing the analysis outputs/errors.
  - `.command.err`: file which lists the errors, if any.


### Output

Pipeline makes the following output (most relevant files outlined):

```
|--output
  |--outputfolder_gen
  |   |--gen_data_QCd
  |   |   |--chrAll_ToImputation.bed
  |   |   |--chrAll_ToImputation.bim
  |   |   |--chrAll_ToImputation.fam
  |   |   |--SexCheck.txt
  |   |   |--...
  |   |--gen_PCs
  |   |   |--GenotypePCs.txt
  |   |--gen_data_summary
  |   |   |--1000G_PC_projections.txt
  |   |   |--vcf_filtering
  |   |   |   |--chr*_filtered.vcf.gz
  |   |   |   |--chr*_filtered.vcf.gz.csi
  |   |   |   |--chr*_prefilter.stats.txt
  |   |   |   |--chr*_filtered.stats.txt
  |   |   |   |--chr*_prefilter.variant_metrics.tsv
  |   |   |   |--chr*_filtered.variant_metrics.tsv
  |   |--gen_plots
  |   |   |--...
  |--vcf_filtering
  |   |--chr*_filtered.vcf.gz
  |   |--chr*_filtered.vcf.gz.csi
  |   |--chr*_prefilter.stats.txt
  |   |--chr*_filtered.stats.txt
  |   |--chr*_prefilter.variant_metrics.tsv
  |   |--chr*_filtered.variant_metrics.tsv
  |--Report_DataQc_[cohort name].html
  |--CovariatePCs.txt
  |--pipeline_info
  |   |--Cvdlink_GenotypeQc_report.html
  |   |--Cvdlink_GenotypeQc_timeline.html
  |   |--Cvdlink_GenotypeQc_trace.txt
  |   |--Cvdlink_GenotypeQc_dag.svg
```

Note: The filtered VCF files use standardized variant IDs in `chr:pos_REF_ALT` format.

Note: When running the pipeline with `--bfile` input instead of `--vcf`, the final `vcf_filtering` outputs are not produced and the report shows the VCF-based diagnostics as unavailable.

Note: The HTML report includes a diagnostic for number of genotyped vs imputed variants before QC (per chromosome + combined). This plot/table is shown only when at least one usable indicator field is present in per-chromosome metrics. By default, the pipeline checks common INFO flag names `IMPUTED`/`imputed` and `TYPED`/`typed`, and you can explicitly set `--vcf_genotype_field` for cohort/tool-specific naming.

Note on common naming in tool outputs:
- VCF specification does not reserve standard INFO keys named `typed` or `imputed`; custom INFO keys are allowed and should be declared in VCF header metadata.
- Minimac documentation and historical outputs commonly use imputation quality `R2`/`Rsq` metrics; typed/genotyped status appears as `Genotyped` in info summaries, and in some workflows VCF FILTER labels such as `GENOTYPED`/`GENOTYPED_ONLY` are used.
- Because this naming varies by tool and pipeline, report logic supports both auto-detection and explicit override via `--vcf_genotype_field`.

#### Steps to take

1. Investigate the file `Report_DataQc*.html`, fix any issues with the genotype/gene expression data according to the plots and instructions. You can adjust arguments of the pipeline to adjust certain outlier detection thresholds according to your data.

2. If data had any quality issues, re-run the pipeline when issues are removed, check the `Report_DataQc.html` again.

## Acknowledgements

Genotype QC and covariate preparations make extensive use of the [bigsnpr package](https://privefl.github.io/bigsnpr/) and [plink 2](https://www.cog-genomics.org/plink/2.0/).

Gene expression processing makes use of [preprocesscore](https://bioconductor.org/packages/release/bioc/html/preprocessCore.html) and [edgeR](https://bioconductor.org/packages/release/bioc/html/edgeR.html) R packages.

### Citation

[Privé, F., Luu, K., Blum, M. G. B., McGrath, J. J., &#38; Vilhjálmsson, B. J. (2020). Efficient toolkit implementing best practices for principal component analysis of population genetic data. <i>Bioinformatics</i>, <i>36</i>(16), 4449–4457. https://doi.org/10.1093/BIOINFORMATICS/BTAA520](https://academic.oup.com/bioinformatics/article/36/16/4449/5838185)

[Chang, C. C., Chow, C. C., Tellier, L. C. A. M., Vattikuti, S., Purcell, S. M., &#38; Lee, J. J. (2015). Second-generation PLINK: Rising to the challenge of larger and richer datasets. GigaScience, 4(1). https://doi.org/10.1186/s13742-015-0047-8](https://academic.oup.com/gigascience/article/4/1/s13742-015-0047-8/2707533)

[Bolstad B (2021). preprocessCore: A collection of pre-processing functions. R package version 1.56.0, https://github.com/bmbolstad/preprocessCore.](https://bioconductor.org/packages/release/bioc/html/preprocessCore.html)

[Robinson MD, McCarthy DJ, Smyth GK (2010). “edgeR: a Bioconductor package for differential expression analysis of digital gene expression data.” Bioinformatics, 26(1), 139-140. doi: 10.1093/bioinformatics/btp616.](10.1093/bioinformatics/btp616)

### Contacts

For this Nextflow pipeline: urmo.vosa at gmail.com.