FROM --platform=linux/amd64 ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG MINIFORGE_VERSION=24.11.0-0
ARG NXF_VER=25.04.8

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    bzip2 \
    ca-certificates \
    curl \
    file \
    fonts-dejavu-core \
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

ENV PATH="/opt/conda/envs/genotypeqc/bin:/opt/conda/bin:${PATH}"
ENV NXF_VER="${NXF_VER}"

RUN Rscript -e "install.packages('R.utils', repos = 'https://cloud.r-project.org')" \
 && Rscript -e "remotes::install_version('bigsnpr', version = '1.10.8', dependencies = TRUE, repos = 'https://cloud.r-project.org', upgrade = 'never')"

RUN curl -fsSL https://get.nextflow.io | bash \
 && mv nextflow /usr/local/bin/nextflow \
 && chmod +x /usr/local/bin/nextflow

COPY . /opt/genotypeqc

RUN chmod +x /opt/genotypeqc/docker-entrypoint.sh /opt/genotypeqc/scripts/offline_fetch.sh \
 && /opt/genotypeqc/scripts/offline_fetch.sh --skip-restricted-assets /opt/genotypeqc/.runtime

ENV GENOTYPEQC_HOME=/opt/genotypeqc
ENV PATH="/opt/genotypeqc/.runtime/bin:/opt/conda/envs/genotypeqc/bin:/opt/conda/bin:/usr/local/bin:${PATH}"

WORKDIR /workspace

ENTRYPOINT ["/opt/genotypeqc/docker-entrypoint.sh"]
