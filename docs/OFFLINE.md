# Offline/isolated setup (host runtime)

If you use the bundled Docker image from the main README, PLINK, Nextflow, the 1000G reference, and the liftOver chain files are already inside the image. The instructions below only apply to host or scheduler runs that stay outside that bundled image.

This pipeline can run without internet access if you provide the required large assets locally. Do **not** commit these large assets to the repo.

## What to keep outside the repo (download separately)

- Container images: `singularity_img/`
- PLINK executables: `plink`, `plink2`
- 1000G reference folder
- LiftOver chain files (only if using hg38/GRCh38)
- Nextflow binary (if not already provided by the system)

## What can be stored in the repo

- This document and helper scripts
- Checksums/manifest files
- Sample run templates

## Expected local layout (example)

```
OFFLINE_ROOT/
  plink_executables/
    plink
    plink2
  1000G_reference/
    1000G_phase3_common_norel.*
  chain_folder/              # only for hg38/GRCh38
    hg19ToHg38.over.chain.gz
    hg38ToHg19.over.chain.gz
  singularity_img/
    *.sif
```

Copy or symlink the container images into the repo so Nextflow finds them:

```
cp -R OFFLINE_ROOT/singularity_img ./singularity_img
```

## Run arguments (offline)

Pass the local paths using the optional parameters:

- `--plink_executable OFFLINE_ROOT/plink_executables/plink`
- `--plink2_executable OFFLINE_ROOT/plink_executables/plink2`
- `--reference_1000g_folder OFFLINE_ROOT/1000G_reference`
- `--chain_path OFFLINE_ROOT/chain_folder` (only for hg38/GRCh38)

## Environment settings

Set the following to prevent online checks/downloads:

- `NXF_OFFLINE=TRUE`
- `SINGULARITY_CACHEDIR` and `NXF_HOME` to local writable paths

## Reference

Official offline instructions: https://eqtlgen.github.io/eqtlgen-web-site/eQTLGen-p2-offline-instructions.html
