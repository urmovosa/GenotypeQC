FROM --platform=linux/amd64 ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG MINIFORGE_VERSION=24.11.0-0
ARG NXF_VER=25.04.8
ARG PLINK_VERSION=20220402
ARG PLINK2_VERSION=20221024

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    bzip2 \
    ca-certificates \
    curl \
    file \
    gfortran \
    git \
    libcurl4-openssl-dev \
    libfontconfig1 \
    libfreetype6-dev \
    libfribidi-dev \
    libharfbuzz-dev \
    libjpeg-dev \
    libpng-dev \
    libssl-dev \
    libtiff5-dev \
    libxml2-dev \
    make \
    openjdk-17-jre-headless \
    procps \
    unzip \
    wget \
    zlib1g-dev \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/miniforge.sh \
       "https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE_VERSION}/Miniforge3-Linux-x86_64.sh" \
 && bash /tmp/miniforge.sh -b -p /opt/conda \
 && rm -f /tmp/miniforge.sh \
 && /opt/conda/bin/conda clean -afy

COPY environment.yml /tmp/environment.yml

RUN /opt/conda/bin/mamba env create -f /tmp/environment.yml \
 && /opt/conda/bin/conda clean -afy \
 && rm -f /tmp/environment.yml

ENV PATH="/opt/conda/envs/eQTLGenPopAssign/bin:/opt/conda/bin:${PATH}"
ENV NXF_VER="${NXF_VER}"

RUN Rscript -e "install.packages('R.utils', repos = 'https://cloud.r-project.org')" \
 && Rscript -e "remotes::install_version('bigsnpr', version = '1.10.8', dependencies = TRUE, repos = 'https://cloud.r-project.org', upgrade = 'never')" \
 && Rscript -e "if (!requireNamespace('preprocessCore', quietly = TRUE)) { if (!requireNamespace('BiocManager', quietly = TRUE)) install.packages('BiocManager', repos = 'https://cloud.r-project.org'); BiocManager::install('preprocessCore', ask = FALSE, update = FALSE) }"

RUN curl -fsSL https://get.nextflow.io | bash \
 && mv nextflow /usr/local/bin/nextflow \
 && chmod +x /usr/local/bin/nextflow

COPY . /opt/genotypeqc

RUN mkdir -p /opt/genotypeqc/.runtime/bin /opt/genotypeqc/.runtime/reference_1000g /opt/genotypeqc/.runtime/chain \
 && curl -fsSL -o /tmp/plink.zip \
       "https://s3.amazonaws.com/plink1-assets/plink_linux_x86_64_${PLINK_VERSION}.zip" \
 && unzip -j /tmp/plink.zip plink -d /opt/genotypeqc/.runtime/bin \
 && curl -fsSL -o /tmp/plink2.zip \
       "https://s3.amazonaws.com/plink2-assets/alpha3/plink2_linux_x86_64_${PLINK2_VERSION}.zip" \
 && unzip -j /tmp/plink2.zip plink2 -d /opt/genotypeqc/.runtime/bin \
 && rm -f /tmp/plink.zip /tmp/plink2.zip \
 && curl -fsSL -o /opt/genotypeqc/.runtime/chain/hg19ToHg38.over.chain.gz \
       "https://hgdownload.soe.ucsc.edu/goldenPath/hg19/liftOver/hg19ToHg38.over.chain.gz" \
 && curl -fsSL -o /opt/genotypeqc/.runtime/chain/hg38ToHg19.over.chain.gz \
       "https://hgdownload.soe.ucsc.edu/goldenPath/hg38/liftOver/hg38ToHg19.over.chain.gz" \
 && chmod +x /opt/genotypeqc/.runtime/bin/plink /opt/genotypeqc/.runtime/bin/plink2 /opt/genotypeqc/bin/liftOver /opt/genotypeqc/docker-entrypoint.sh \
 && Rscript -e "library(bigsnpr); download_1000G('/opt/genotypeqc/.runtime/reference_1000g')"

ENV GENOTYPEQC_HOME=/opt/genotypeqc
ENV PATH="/opt/genotypeqc/.runtime/bin:/opt/conda/envs/eQTLGenPopAssign/bin:/opt/conda/bin:/usr/local/bin:${PATH}"

WORKDIR /workspace

ENTRYPOINT ["/opt/genotypeqc/docker-entrypoint.sh"]
