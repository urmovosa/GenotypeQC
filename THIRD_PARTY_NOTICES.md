# Third-Party Notices

This file identifies third-party components distributed in the public GenotypeQC container image and the separately staged assets required for offline runs. It is not a substitute for the upstream license texts.

## Public Container Image

| Component | License or terms | Source and corresponding source |
|---|---|---|
| Ubuntu base packages | Component-specific licenses | https://packages.ubuntu.com/ |
| Miniforge and Conda packages | Component-specific licenses | https://github.com/conda-forge/miniforge/blob/main/LICENSE |
| PLINK 2 | GPL-3.0; source tree also includes LGPL-3.0 components | https://github.com/chrchang/plink-ng/tree/master/2.0 |
| bigsnpr 1.10.8 | GPL-3.0 | https://cran.r-project.org/src/contrib/Archive/bigsnpr/ |
| R.utils | GPL-2.0-or-later | https://cran.r-project.org/package=R.utils |
| Nextflow | Apache-2.0 | https://github.com/nextflow-io/nextflow |
| 1000 Genomes Phase 3 derived PLINK reference | Data-use terms and citation requirements apply | https://www.internationalgenome.org/IGSR_disclaimer |
| DejaVu fonts | Bitstream Vera and DejaVu license terms | https://dejavu-fonts.github.io/License.html |

The image obtains the 1000 Genomes reference through `bigsnpr::download_1000G()`. That function downloads the `1000G_phase3_common_norel` archive from Figshare. Users should cite the 1000 Genomes Project phase 3 publication and check the current IGSR data-use terms before redistributing derived data.

## Separately Staged Restricted Assets

The public image intentionally excludes the assets below. `scripts/offline_stage.sh` retrieves them into the local `offline_runtime/` bundle for the operator's controlled offline deployment.

| Component | Terms | Source |
|---|---|---|
| UCSC LiftOver executable | Non-commercial use unless separately licensed by UCSC | https://genome.ucsc.edu/license/ |
| UCSC hg19-to-hg38 and hg38-to-hg19 chain files | May be linked, downloaded, used, and redistributed only for non-commercial use | https://genome.ucsc.edu/license/ |

Do not publish the `offline_runtime/` directory in a public image or public artifact unless you have confirmed that your intended use and redistribution are permitted by UCSC's current terms.

## Removed Proprietary Dependency

The public image does not include Microsoft Core Fonts. Their license restricts redistribution for profit, so `mscorefonts` was replaced with the open DejaVu font package (used as fallback font in the pipeline HTML report).