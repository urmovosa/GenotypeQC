# CVDLINK Genotype QC Pipeline

Automatic QC pipeline with checks, processing and reporting for genotype data in .vcf format (or PLINK bed/bim/fam input).

## Pipeline Overview

The pipeline performs the following main steps:

- Genotype QC and filtering:
  - In VCF mode, converts each chromosome to a PLINK dataset and merges the full input variant set before sample QC, PCA, and ancestry projection. In PLINK mode, starts directly from the supplied bed/bim/fam prefix.
  - Applies HWE and MAF filters to the full post-sample-QC VCF. For imputed input, an optional imputation-quality filter is enabled by default.
  - Applies sample-level missingness filtering.
  - Compares reported and genetic sex when known sex is supplied in a `.fam` file, and removes mismatched or unclear samples.
  - Removes samples with excess heterozygosity (+/-3 SD from the mean).
  - Removes related samples so that one sample from each related pair is kept in the data.
  - Projects samples into the 1000 Genomes reference space, harmonizes between hg19/GRCh37 and hg38/GRCh38 when needed, and flags genetic outliers.
  - Calculates the first 10 genetic principal components (PCs), used in downstream analyses as covariates to correct for population stratification.
  - Filters the full input dataset to exclude samples and variants failing QC, using mode-appropriate thresholds for array, imputed, or WGS data.
- Additional steps:
  - Organizes the QCd genotype data into the standard output folder structure.
  - Writes summary tables, ancestry projection outputs, and covariate files for downstream analysis.
  - Provides a commented `html` QC report that gives an overview of the quality of the data and supports follow-up decisions.

## Requirements

- Production offline runs: Bash >= 3.2, Java >= 17, Nextflow, and Apptainer or Singularity.
- Staging machine: the same requirements as the offline target, plus network access to pull the public image.
- Local Docker runs: Docker only.
- Non-container development runs: Bash >= 3.2, Java >= 17, Nextflow, R, and the development runtime cache.
- For VCF input: one `.vcf.gz` per chromosome in a single directory.

Bundled static resources kept in the repo:

- `data/1000G_pops.txt`
- `data/unrelated_reference_samples_ids.txt`
- `data/validation_snps.tsv`

The public container image includes R, PLINK2, and the 1000G reference. During staging, the script retrieves UCSC LiftOver and chain files into a local `offline_runtime/` bundle. Production runs do not download assets or send input data over the network.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the included-component notices and the separate terms that apply to locally staged UCSC assets.

## Quick Start

### Offline Apptainer Or Singularity Run

This is the recommended workflow for privacy-sensitive data. Prepare a local bundle while the staging machine has network access, then run only from local files after disconnecting it or copying the bundle to an offline Linux HPC cluster.

The staging and target machines must be Linux x86_64. Start from a repository checkout on the connected staging machine:

```bash
git clone https://github.com/urmovosa/GenotypeQC.git
cd GenotypeQC
scripts/offline_stage.sh --platform linux-x86_64
```

The script reports missing Java, Nextflow, and Apptainer or Singularity. When it completes, `.offline_bundle/` contains a local SIF image, local UCSC LiftOver assets, warmed Nextflow runtime, and `offline-env.sh`.

To use a separate offline cluster, copy both the repository checkout and `.offline_bundle/` to the cluster. Also copy a Nextflow launcher if the cluster does not provide `nextflow`.

On the offline machine, source the generated environment and run against your own input directory:

Per-chromosome VCF input:

```bash
source /path/to/GenotypeQC/.offline_bundle/offline-env.sh

NXF_SYNTAX_PARSER=v1 nextflow run /path/to/GenotypeQC/main.nf \
  -profile local_vm,singularity \
  --container_image "$GENOTYPEQC_CONTAINER_IMAGE" \
  --offline_runtime_dir "$GENOTYPEQC_OFFLINE_RUNTIME_DIR" \
  --vcf /absolute/path/to/imputed_vcfs \
  --data_type imputed \
  --cohort_name cohort_a \
  --genome_build GRCh38 \
  --output_dir /absolute/path/to/results/cohort_a \
  -resume
```

PLINK bed/bim/fam input:

```bash
source /path/to/GenotypeQC/.offline_bundle/offline-env.sh

NXF_SYNTAX_PARSER=v1 nextflow run /path/to/GenotypeQC/main.nf \
  -profile local_vm,singularity \
  --container_image "$GENOTYPEQC_CONTAINER_IMAGE" \
  --offline_runtime_dir "$GENOTYPEQC_OFFLINE_RUNTIME_DIR" \
  --bfile /absolute/path/to/study_prefix \
  --data_type array \
  --cohort_name cohort_a \
  --genome_build GRCh37 \
  --output_dir /absolute/path/to/results/cohort_a \
  -resume
```

For Slurm, replace `local_vm` with `slurm`. The included [scheduler template](scripts/submit_CVDLinkGenotypeQC_pipeline_template.sh) uses the staged local SIF by default.

The `NXF_OFFLINE=TRUE` value set by `offline-env.sh` prevents Nextflow from downloading pipeline code or runtime components. With a local SIF path, no task needs registry access and genotype data stays on the offline machine or cluster.

### Local Docker Run

Docker is convenient for a connected workstation. Pull the published image:

```bash
docker pull ghcr.io/urmovosa/genotypeqc:latest
```

Run with VCF input. The image entrypoint adds `-profile single_docker` automatically:

```bash
docker run --rm -it \
  --platform linux/amd64 \
  -v "$PWD:/workspace" \
  -v /absolute/path/to/input:/input:ro \
  -v /absolute/path/to/offline_runtime:/offline-runtime:ro \
  -e GENOTYPEQC_OFFLINE_RUNTIME_DIR=/offline-runtime \
  ghcr.io/urmovosa/genotypeqc:latest \
  --vcf /input/imputed_vcfs \
  --data_type imputed \
  --cohort_name cohort_a \
  --genome_build GRCh38 \
  --output_dir /workspace/results/cohort_a \
  -resume
```

Notes:

- Mount a writable `/workspace` so Nextflow can persist `.nextflow/`, `work/`, and outputs between runs.
- On Apple Silicon, build and run the image as `linux/amd64` because the bundled runtime is `x86_64`.
- The image contains the public runtime; LiftOver and chain files come from the read-only `offline_runtime/` mount.

### Development-Mode Host Run

Running without a container is for development only. It requires R and all pipeline-specific binaries and reference data on the host. Prepare the development cache on a connected Linux x86_64 machine:


```bash
scripts/offline_stage.sh --platform linux-x86_64 --development-runtime-cache
```

Then run locally:

```bash
NXF_SYNTAX_PARSER=v1 nextflow run main.nf \
  -profile local_vm \
  --runtime_cache_dir .offline_bundle/development_runtime_cache \
  --bfile /absolute/path/to/study_prefix \
  --data_type array \
  --cohort_name cohort_a \
  --genome_build GRCh37 \
  --output_dir /absolute/path/to/results/cohort_a \
  -resume
```

## Required Arguments

- `--cohort_name` Cohort label used in reports and output names.
- `--genome_build` One of `hg18`, `GRCh36`, `hg19`, `GRCh37`, `hg38`, or `GRCh38`.
- `--data_type` Input mode: `array`, `imputed`, or `wgs`. Use `array` with `--bfile`; `imputed` and `wgs` require `--vcf`. Default: `array`.
- `--vcf` Directory containing per-chromosome `.vcf.gz` files, or
- `--bfile` PLINK prefix without `.bed/.bim/.fam` extensions.
- `--output_dir` Output directory.

## Common Optional Arguments

- `--fam` Optional PLINK `.fam` file with known sex annotations.
- `--inclusion_list` File with sample IDs to keep.
- `--exclusion_list` File with sample IDs to remove.
- `--additional_covariates` Tab-separated file with extra covariates. The first column must be `SampleID`.
- `--qc_out_s` Outlierness threshold for ancestry outlier detection. Default: `0.4`.
- `--qc_out_sd` PC-based outlier threshold in SD units. Default: `3`.
- `--qc_hwe` HWE threshold for genotype QC. Default: `1e-6`.
- `--qc_maf` MAF threshold for genotype QC. Default: `0.01`.
- `--vcf_maf` MAF threshold for final VCF filtering. Default: `0.01`.
- `--vcf_hwe` HWE threshold for final VCF filtering. Default: `1e-6`.
- `--enable_imputation_filter` Apply the imputation-quality filter in `imputed` mode. Default: `true`. Set to `false` when the source lacks a suitable quality field or the filter is not wanted.
- `--vcf_imp` Minimum imputation quality threshold in `imputed` mode. Default: `0.8`.
- `--vcf_imp_field` INFO sub-field containing imputation quality in `imputed` mode. Default: `R2`.
- `--vcf_genotype_field` Optional INFO sub-field indicating typed/genotyped vs imputed variants.

Development-only runtime options are documented in [scripts/OFFLINE.md](scripts/OFFLINE.md).

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
- Imputation-quality and typed-vs-imputed report diagnostics are shown only for `--data_type imputed`. Set `--vcf_genotype_field` when your source uses a cohort-specific indicator field.
- WGS reports summarize SNPs, indels, other variants, and transition/transversion ratios from `bcftools stats`; no imputation field is required or used.

## Debugging

- Re-run failed pipelines with the same command plus `-resume`.
- Inspect `pipeline_info/GenotypeQC_report.html` for task-level failures and work directories.
- For a failed task, inspect `.command.sh`, `.command.log`, and `.command.err` in the corresponding `work/` directory.

## License

GenotypeQC source code is licensed under the GNU General Public License, version 3 or later. See [LICENSE](LICENSE).

The license applies to this repository's code. Container dependencies, the 1000 Genomes reference, and the separately staged `offline_runtime/` assets remain subject to their own terms. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Acknowledgements

Genotype QC and covariate preparations make extensive use of [bigsnpr](https://privefl.github.io/bigsnpr/) and [PLINK 2](https://www.cog-genomics.org/plink/2.0/).

## Citations

- Prive, F., Luu, K., Blum, M. G. B., McGrath, J. J., and Vilhjalmsson, B. J. (2020). Efficient toolkit implementing best practices for principal component analysis of population genetic data. Bioinformatics, 36(16), 4449-4457. https://doi.org/10.1093/bioinformatics/btaa520
- Chang, C. C., Chow, C. C., Tellier, L. C. A. M., Vattikuti, S., Purcell, S. M., and Lee, J. J. (2015). Second-generation PLINK: Rising to the challenge of larger and richer datasets. GigaScience, 4(1). https://doi.org/10.1186/s13742-015-0047-8

## Contacts

- Urmo Võsa: urmo.vosa at gmail.com
- Andres Veidenberg: andres.veidenberg at gmail.com