# CVDLINK Genotype QC Pipeline

Automatic QC pipeline with checks, processing and reporting for genotype data in .vcf format (or PLINK bed/bim/fam input).

## Pipeline Overview

The pipeline performs the following main steps:

- Genotype QC and filtering:
  - In VCF mode, converts each chromosome to a PLINK dataset on the bundled HapMap3 marker subset before merging. In PLINK mode, starts directly from the supplied bed/bim/fam prefix.
  - Applies standard variant QC filtering on the HapMap3 subset used for QC and ancestry projection, including variant missingness, Hardy-Weinberg equilibrium, and minor allele frequency thresholds.
  - Applies sample-level missingness filtering.
  - Compares reported and genetic sex when known sex is supplied in a `.fam` file, and removes mismatched or unclear samples.
  - Removes samples with excess heterozygosity (+/-3 SD from the mean).
  - Removes related samples so that one sample from each related pair is kept in the data.
  - Projects samples into the 1000 Genomes reference space, harmonizes between hg19/GRCh37 and hg38/GRCh38 when needed, and flags genetic outliers.
  - Calculates the first 10 genetic principal components (PCs), used in downstream analyses as covariates to correct for population stratification.
  - Filters the full imputed dataset to exclude samples and variants failing QC, with adjustable HWE, MAF, and imputation-quality thresholds when VCF input is provided.
- Additional steps:
  - Organizes the QCd genotype data into the standard output folder structure.
  - Writes summary tables, ancestry projection outputs, and covariate files for downstream analysis.
  - Provides a commented `html` QC report that gives an overview of the quality of the data and supports follow-up decisions.

## Requirements

- Host or scheduler runs: Bash >= 3.2, Java >= 17, Nextflow, and either Apptainer/Singularity or Docker.
- Single-image Docker runs: Docker only.
- For VCF input: one `.vcf.gz` per chromosome in a single directory.

Bundled static resources kept in the repo:

- `data/hapmap3_snps.tsv`
- `data/1000G_pops.txt`
- `data/unrelated_reference_samples_ids.txt`
- `data/validation_snps.tsv`

Large runtime assets are not committed. Host runs populate a reusable cache in `.runtime_downloads/` by default.

## Quick Start

### Host run

Per-chromosome VCF input:

```bash
NXF_SYNTAX_PARSER=v1 nextflow run main.nf \
  -profile local_vm \
  --vcf /absolute/path/to/imputed_vcfs \
  --cohort_name cohort_a \
  --genome_build GRCh38 \
  --output_dir results/cohort_a \
  -resume
```

PLINK bed/bim/fam input:

```bash
NXF_SYNTAX_PARSER=v1 nextflow run main.nf \
  -profile local_vm \
  --bfile /absolute/path/to/study_prefix \
  --cohort_name cohort_a \
  --genome_build GRCh37 \
  --output_dir results/cohort_a \
  -resume
```

The first successful host-side run automatically seeds `.runtime_downloads/` with the required PLINK 2 binary, liftOver binary, chain files, and 1000G reference. That cache can then be reused across runs or copied to an offline host.

### Single Docker image

Build the image:

```bash
docker buildx build --platform linux/amd64 --load -t genotypeqc:latest .
```

Run with VCF input. The image entrypoint adds `-profile single_docker` automatically:

```bash
docker run --rm -it \
  --platform linux/amd64 \
  -v "$PWD:/workspace" \
  -v /absolute/path/to/input:/input:ro \
  genotypeqc:latest \
  --vcf /input/imputed_vcfs \
  --cohort_name cohort_a \
  --genome_build GRCh38 \
  --output_dir /workspace/results/cohort_a \
  -resume
```

Notes:

- Mount a writable `/workspace` so Nextflow can persist `.nextflow/`, `work/`, and outputs between runs.
- On Apple Silicon, build and run the image as `linux/amd64` because the bundled runtime is `x86_64`.
- In `single_docker`, the PLINK binaries, liftOver executable, chain files, and 1000G reference are already bundled.

### Scheduler runs

Use the generic scheduler template in `submit_GenotypeQC_pipeline_template.sh` and adjust the profile for your environment:

- Slurm: `-profile slurm,singularity`
- PBS/TORQUE: `-profile pbs,singularity`
- SGE: `-profile sge,singularity`
- Single host without scheduler: `-profile local_vm,singularity`

## Required Arguments

- `--cohort_name` Cohort label used in reports and output names.
- `--genome_build` One of `hg18`, `GRCh36`, `hg19`, `GRCh37`, `hg38`, or `GRCh38`.
- `--vcf` Directory containing per-chromosome `.vcf.gz` files, or
- `--bfile` PLINK prefix without `.bed/.bim/.fam` extensions.
- `--output_dir` Output directory.

## Common Optional Arguments

- `--fam` Optional PLINK `.fam` file with known sex annotations.
- `--inclusion_list` File with sample IDs to keep.
- `--exclusion_list` File with sample IDs to remove.
- `--additional_covariates` Tab-separated file with extra covariates. The first column must be `SampleID`.
- `--runtime_cache_dir` Host-side cache for auto-downloaded runtime assets. Default: `$baseDir/.runtime_downloads`.
- `--plink2_executable` Override the PLINK 2 binary path.
- `--plink_executable` Override the PLINK-compatible binary path. By default host runs reuse the cached PLINK 2 binary.
- `--reference_1000g_folder` Override the 1000G reference directory.
- `--chain_path` Override the directory containing `hg19ToHg38.over.chain.gz` and `hg38ToHg19.over.chain.gz`.
- `--liftover_executable` Override the UCSC liftOver binary path.
- `--snpfilter` Override the bundled HapMap3 variant list.
- `--qc_out_s` Outlierness threshold for ancestry outlier detection. Default: `0.4`.
- `--qc_out_sd` PC-based outlier threshold in SD units. Default: `3`.
- `--qc_hwe` HWE threshold for genotype QC. Default: `1e-6`.
- `--qc_maf` MAF threshold for genotype QC. Default: `0.01`.
- `--vcf_maf` MAF threshold for final VCF filtering. Default: `0.01`.
- `--vcf_hwe` HWE threshold for final VCF filtering. Default: `1e-6`.
- `--vcf_imp` Minimum imputation quality threshold for final VCF filtering. Default: `0.8`.
- `--vcf_imp_field` INFO sub-field containing imputation quality. Default: `R2`.
- `--vcf_genotype_field` Optional INFO sub-field indicating typed/genotyped vs imputed variants.

## Offline Use

Host and scheduler runs can be taken offline after the runtime cache has been prepared.

Two supported preparation paths:

1. Run the pipeline once online and reuse the populated `.runtime_downloads/` cache.
2. Preload the cache with `scripts/offline_fetch.sh`.

Detailed instructions are in `docs/OFFLINE.md`.

If you use the bundled Docker image, the required runtime assets are already inside the image and no extra cache preparation is needed.

## Outputs

Key outputs under `--output_dir`:

- `Report_DataQc_<cohort>.html`
- `CovariatePCs.txt`
- `outputfolder_gen/gen_data_QCd/`
- `outputfolder_gen/gen_PCs/GenotypePCs.txt`
- `outputfolder_gen/gen_data_summary/1000G_PC_projections.txt`
- `pipeline_info/GenotypeQC_report.html`
- `pipeline_info/GenotypeQC_timeline.html`
- `pipeline_info/GenotypeQC_trace.txt`
- `pipeline_info/GenotypeQC_dag.svg`
- `vcf_filtering/` when the input was `--vcf`

Notes:

- Filtered VCF outputs use standardized variant IDs in `chr:pos_REF_ALT` format.
- When the input is `--bfile`, the final `vcf_filtering/` outputs are not produced.
- The typed-vs-imputed report diagnostic is shown only when the input VCF metrics contain a usable indicator field. Set `--vcf_genotype_field` when your source uses cohort-specific naming.

## Debugging

- Re-run failed pipelines with the same command plus `-resume`.
- Inspect `pipeline_info/GenotypeQC_report.html` for task-level failures and work directories.
- For a failed task, inspect `.command.sh`, `.command.log`, and `.command.err` in the corresponding `work/` directory.

## Acknowledgements

Genotype QC and covariate preparations make extensive use of [bigsnpr](https://privefl.github.io/bigsnpr/) and [PLINK 2](https://www.cog-genomics.org/plink/2.0/).

## Citations

- Prive, F., Luu, K., Blum, M. G. B., McGrath, J. J., and Vilhjalmsson, B. J. (2020). Efficient toolkit implementing best practices for principal component analysis of population genetic data. Bioinformatics, 36(16), 4449-4457. https://doi.org/10.1093/bioinformatics/btaa520
- Chang, C. C., Chow, C. C., Tellier, L. C. A. M., Vattikuti, S., Purcell, S. M., and Lee, J. J. (2015). Second-generation PLINK: Rising to the challenge of larger and richer datasets. GigaScience, 4(1). https://doi.org/10.1186/s13742-015-0047-8

## Contacts

- Urmo Vosa: urmo.vosa at gmail.com
- Andres Veidenberg: andres.veidenberg at gmail.com