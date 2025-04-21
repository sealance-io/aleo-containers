# syntax=docker/dockerfile:1.2

ARG NODE_VERSION=22
ARG DEBIAN_RELEASE=bookworm
ARG RUST_VERSION=1.85.1

# Stage 1: Build leo-lang from source
FROM rust:${RUST_VERSION}-slim-${DEBIAN_RELEASE} as builder

ARG LEO_VERSION=v2.5.0
ARG LEO_REPO=https://github.com/ProvableHQ/leo
# Force rust to use external Git instead of the internal libgit wrapper
ENV CARGO_NET_GIT_FETCH_WITH_CLI=true

# Install build dependencies in a single layer
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    git \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Clone repo and build Leo CLI
RUN git clone -b "${LEO_VERSION}" --recurse-submodules --single-branch --depth 1 "${LEO_REPO}"

WORKDIR /app/leo

# Ensure we use the specified Rust version (required by snarkvm)
ARG RUST_VERSION
RUN rustup toolchain install ${RUST_VERSION} --force && rustup default ${RUST_VERSION}

# Compile with optimizations
RUN cargo +${RUST_VERSION} install --path .

# Stage 2: Create minimal leo image
FROM node:${NODE_VERSION}-${DEBIAN_RELEASE}-slim as leo

LABEL org.opencontainers.image.source="${LEO_REPO}"
LABEL org.opencontainers.image.description="Leo CLI with NodeJS environment"

# Copy leo-lang binary from the builder stage
COPY --from=builder /usr/local/cargo/bin/leo /usr/local/bin/

# Set path to make leo-lang easily accessible
ENV PATH="/usr/local/bin:${PATH}"

# Install required packages - minimal set only
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl-dev \
    curl \
    ca-certificates \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --chmod=755 download-provers.sh /tmp/
RUN /tmp/download-provers.sh

# Set appropriate workdir
WORKDIR /app

# Add version verification script
RUN echo '#!/bin/sh' > /usr/local/bin/check-versions \
    && echo 'echo "Installed tools:"' >> /usr/local/bin/check-versions \
    && echo 'echo "- Leo: $(leo --version)"' >> /usr/local/bin/check-versions \
    && echo 'echo "- Node.js: $(node --version)"' >> /usr/local/bin/check-versions \
    && echo 'echo "- NPM: $(npm --version)"' >> /usr/local/bin/check-versions \
    && chmod +x /usr/local/bin/check-versions

# Default command to show installed versions
CMD ["check-versions"]

# Stage 3: Create CI image with full toolchains
FROM debian:${DEBIAN_RELEASE} as leo-ci

ARG LEO_REPO
LABEL org.opencontainers.image.source="${LEO_REPO}"
LABEL org.opencontainers.image.description="Leo CLI with full development and CI environment"

# Install Node.js - reusing the specified version
ARG NODE_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    gnupg \
    lsb-release \
    && curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && update-ca-certificates

# Install Rust toolchain
ARG RUST_VERSION
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain ${RUST_VERSION} \
    && echo 'source $HOME/.cargo/env' >> $HOME/.bashrc

# Add Rust binaries to PATH
ENV PATH="/root/.cargo/bin:${PATH}"

# Copy leo-lang binary from the builder stage
COPY --from=builder /usr/local/cargo/bin/leo /usr/local/bin/

# Install CI/CD dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    git-lfs \
    libssl-dev \
    pkg-config \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# Install Docker Compose V2
RUN mkdir -p /usr/local/lib/docker/cli-plugins \
    && curl -SL https://github.com/docker/compose/releases/download/v2.23.3/docker-compose-linux-$(uname -m) -o /usr/local/lib/docker/cli-plugins/docker-compose \
    && chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Set up environment for GitHub Actions
RUN echo "export DOCKER_BUILDKIT=1" >> /etc/profile \
    && echo "export DOCKER_CLI_EXPERIMENTAL=enabled" >> /etc/profile

# Create workspace directory for GitHub Actions
RUN mkdir -p /github/workspace
ENV WORKDIR=/github/workspace

COPY --chmod=755 download-provers.sh /tmp/
RUN /tmp/download-provers.sh

# Set appropriate workdir
WORKDIR /app
RUN ln -s /github/workspace /app/workspace

# Add version verification script with additional tools
RUN echo '#!/bin/sh' > /usr/local/bin/check-versions \
    && echo 'echo "Installed tools:"' >> /usr/local/bin/check-versions \
    && echo 'echo "- Leo: $(leo --version)"' >> /usr/local/bin/check-versions \
    && echo 'echo "- Node.js: $(node --version)"' >> /usr/local/bin/check-versions \
    && echo 'echo "- NPM: $(npm --version)"' >> /usr/local/bin/check-versions \
    && echo 'echo "- Rust: $(rustc --version)"' >> /usr/local/bin/check-versions \
    && echo 'echo "- Cargo: $(cargo --version)"' >> /usr/local/bin/check-versions \
    && echo 'echo "- Git: $(git --version)"' >> /usr/local/bin/check-versions \
    && echo 'echo "- Docker: $(docker --version)"' >> /usr/local/bin/check-versions \
    && echo 'echo "- Docker Compose: $(docker compose version)"' >> /usr/local/bin/check-versions \
    && echo 'echo "- libssl-dev: $(dpkg-query -W -f='\''${Version}\\n'\'' libssl-dev)"' >> /usr/local/bin/check-versions \
    && chmod +x /usr/local/bin/check-versions

# Default command to show installed versions
CMD ["check-versions"]