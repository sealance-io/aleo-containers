# syntax=docker/dockerfile:1.2

ARG NODE_VERSION=24
ARG DEBIAN_RELEASE=trixie
# Used to pin Rust base images.
ARG RUST_VERSION=1.96.0

# =============================================================================
# Stage 0: Planner - Generate cargo-chef recipe for dependency caching
# =============================================================================
FROM rust:${RUST_VERSION}-slim-${DEBIAN_RELEASE} as planner

ARG LEO_VERSION=v4.1.0
ARG LEO_SOURCE_TAG=leo-lang-v4.1.0
ARG LEO_REPO=https://github.com/ProvableHQ/leo

# Install cargo-chef and git
RUN cargo install cargo-chef --locked \
    && apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Clone repo and generate recipe.json (captures dependency information)
ENV CARGO_NET_GIT_FETCH_WITH_CLI=true
RUN git clone -b "${LEO_SOURCE_TAG}" --recurse-submodules --single-branch --depth 1 "${LEO_REPO}"

WORKDIR /app/leo
RUN cp rust-toolchain.toml /app/rust-toolchain.toml \
    && cp /app/rust-toolchain.toml rust-toolchain.toml \
    && cargo chef prepare --recipe-path recipe.json

# =============================================================================
# Stage 1: Builder - Compile dependencies (cached) then source
# =============================================================================
FROM rust:${RUST_VERSION}-slim-${DEBIAN_RELEASE} as builder

ARG LEO_VERSION=v4.1.0
ARG LEO_SOURCE_TAG=leo-lang-v4.1.0
ARG LEO_REPO=https://github.com/ProvableHQ/leo

# Force rust to use external Git instead of the internal libgit wrapper
ENV CARGO_NET_GIT_FETCH_WITH_CLI=true

# Install cargo-chef and build dependencies
# clang (libclang) + build-essential are required by librocksdb-sys, a transitive
# dependency introduced in Leo v4.1.0: bindgen needs libclang and the bundled
# RocksDB C++ sources need a C++ compiler. Mirrors aleo-devnet.Dockerfile's snarkOS builder.
RUN cargo install cargo-chef --locked \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    git \
    pkg-config \
    libssl-dev \
    clang \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy recipe from planner and cook dependencies (this layer is cached!)
COPY --from=planner /app/leo/recipe.json recipe.json
COPY --from=planner /app/rust-toolchain.toml rust-toolchain.toml
RUN cargo chef cook --release --recipe-path recipe.json

# Now clone the actual source and build (only this step reruns on source changes)
# Clone to /src to avoid conflict with cargo chef's generated structure
RUN git clone -b "${LEO_SOURCE_TAG}" --recurse-submodules --single-branch --depth 1 "${LEO_REPO}" /src/leo

WORKDIR /src/leo

# Compile with optimizations - dependencies already compiled from cargo chef cook
# Leo v4+ uses a workspace layout (crates/leo/Cargo.toml) requiring -p leo-lang;
# Leo v3 builds from the workspace root without -p.
RUN cp /app/rust-toolchain.toml /src/leo/rust-toolchain.toml \
    && if [ -f crates/leo/Cargo.toml ]; then \
         cargo build --release --locked -p leo-lang; \
       else \
         cargo build --release --locked; \
       fi \
    && cp target/release/leo /usr/local/bin/leo \
    && strip /usr/local/bin/leo

# =============================================================================
# Stage 2: Create minimal leo image
# =============================================================================
FROM node:${NODE_VERSION}-${DEBIAN_RELEASE}-slim as leo

ARG LEO_VERSION=v4.1.0
ARG LEO_SOURCE_TAG=leo-lang-v4.1.0
ARG LEO_REPO=https://github.com/ProvableHQ/leo
LABEL org.opencontainers.image.source="${LEO_REPO}"
LABEL org.opencontainers.image.description="Leo CLI with NodeJS environment"
LABEL leo.version="${LEO_VERSION}"
LABEL leo.source-tag="${LEO_SOURCE_TAG}"

# Copy leo-lang binary from the builder stage
COPY --from=builder /usr/local/bin/leo /usr/local/bin/

# Set path to make leo-lang easily accessible
ENV PATH="/usr/local/bin:${PATH}"

# Install required packages - minimal set only
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl-dev \
    curl \
    ca-certificates \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create group and non-root user 'leo' with home directory
# Using a higher UID to avoid conflicts with existing users
RUN groupadd -g 1001 leo && \
    useradd -m -s /bin/bash -u 1001 -g leo leo

# Create .aleo directory with proper permissions for leo user
RUN mkdir -p /.aleo && chown -R leo:leo /.aleo

# Set appropriate workdir and ensure proper ownership
WORKDIR /app
RUN chown -R leo:leo /app

# Add version verification script
# hadolint ignore=SC2016
RUN echo '#!/bin/sh' > /usr/local/bin/check-versions \
    && echo 'echo "Installed tools:"' >> /usr/local/bin/check-versions \
    && echo 'echo "- Leo: $(leo --version)"' >> /usr/local/bin/check-versions \
    && echo 'echo "- Node.js: $(node --version)"' >> /usr/local/bin/check-versions \
    && echo 'echo "- NPM: $(npm --version)"' >> /usr/local/bin/check-versions \
    && chmod +x /usr/local/bin/check-versions

# Copy download-provers.sh and set ownership
COPY --chmod=755 --chown=leo:leo download-provers.sh /tmp/

# Switch to leo user for all remaining operations
USER leo

# Run the download-provers script as leo user
RUN DEST_DIR="/.aleo/resources/" /tmp/download-provers.sh

# CLI tool image — no long-running service to health-check
HEALTHCHECK NONE

# Default command to show installed versions
CMD ["check-versions"]
