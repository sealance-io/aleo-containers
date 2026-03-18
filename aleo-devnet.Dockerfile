# aleo-devnet.Dockerfile - Leo CLI with snarkOS for local devnet testing
# Build: docker build -f aleo-devnet.Dockerfile -t aleo-devnet .
# Run: docker run -it --rm -p 3030:3030 -p 4130:4130 -v $(pwd)/data:/aleo/data aleo-devnet

# Build arguments
ARG LEO_VERSION=v3.5.0
ARG SNARKOS_VERSION=v4.5.4
# Used to pin Rust base images.
ARG RUST_VERSION=1.92.0

# =============================================================================
# Stage 0: Leo image reference (workaround for --from not supporting ARG)
# =============================================================================
FROM ghcr.io/sealance-io/leo-lang:${LEO_VERSION} AS leo-image

# =============================================================================
# Stage 1: snarkOS Planner - Generate cargo-chef recipe for dependency caching
# =============================================================================
FROM rust:${RUST_VERSION}-trixie AS snarkos-planner

ARG SNARKOS_VERSION

# Install cargo-chef and git
RUN cargo install cargo-chef \
    && apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
ENV CARGO_NET_GIT_FETCH_WITH_CLI=true
RUN git clone --branch ${SNARKOS_VERSION} --depth 1 https://github.com/ProvableHQ/snarkOS.git

WORKDIR /build/snarkOS
RUN cp rust-toolchain.toml /build/rust-toolchain.toml \
    && cp /build/rust-toolchain.toml rust-toolchain.toml \
    && cargo chef prepare --recipe-path recipe.json

# =============================================================================
# Stage 2: Build snarkOS - Dependencies cached via cargo-chef
# =============================================================================
FROM rust:${RUST_VERSION}-trixie AS snarkos-builder

ARG SNARKOS_VERSION

# Install cargo-chef and build dependencies
RUN cargo install cargo-chef \
    && apt-get update && apt-get install -y \
    build-essential \
    clang \
    cmake \
    curl \
    gcc \
    lld \
    libssl-dev \
    libcurl4-openssl-dev \
    llvm \
    make \
    pkg-config \
    protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
ENV CARGO_NET_GIT_FETCH_WITH_CLI=true

# Copy recipe from planner and cook dependencies (this layer is cached!)
COPY --from=snarkos-planner /build/snarkOS/recipe.json recipe.json
COPY --from=snarkos-planner /build/rust-toolchain.toml rust-toolchain.toml
RUN cargo chef cook --release --recipe-path recipe.json \
    --features "default,snarkos-node-metrics,test_network"

# Clone and build snarkOS - dependencies already compiled
# Clone to /src to avoid conflict with cargo chef's generated structure
RUN git clone --branch ${SNARKOS_VERSION} --depth 1 https://github.com/ProvableHQ/snarkOS.git /src/snarkOS

WORKDIR /src/snarkOS

# Build snarkOS in release mode with specified features
# Using the standard feature set for devnet operation
RUN cp /build/rust-toolchain.toml /src/snarkOS/rust-toolchain.toml \
    && cargo build --release --locked \
    --features "default,snarkos-node-metrics,test_network" && \
    mv target/release/snarkos /tmp/snarkos && \
    strip /tmp/snarkos

# =============================================================================
# Stage 3: Final runtime image
# =============================================================================
FROM debian:trixie-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    libcurl4 \
    curl \
    wget \
    procps \
    net-tools \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user 'leo' (matching leo-lang image)
RUN groupadd -g 1001 leo && \
    useradd -m -s /bin/bash -u 1001 -g leo leo

# Set working directory
WORKDIR /aleo

# Copy Leo binary from pre-built image
COPY --from=leo-image /usr/local/bin/leo /usr/local/bin/leo

# Copy snarkOS binary from builder
COPY --from=snarkos-builder /tmp/snarkos /aleo/snarkos

# Make binaries executable
RUN chmod +x /usr/local/bin/leo /aleo/snarkos

# Create directories with proper ownership for leo user
# /aleo/data: blockchain storage (volume mount point)
# /home/leo/.aleo: aleo SDK home directory for provers
RUN mkdir -p /aleo/data && \
    chown -R leo:leo /aleo

# Verify installations (as root, before switching user)
RUN leo --version && \
    ./snarkos --version

# Copy download-provers.sh and set ownership
COPY --chmod=755 --chown=leo:leo download-provers.sh /tmp/

# Switch to non-root user for remaining operations
USER leo

# Download provers to leo user's home directory
RUN DEST_DIR="/home/leo/.aleo/resources/" /tmp/download-provers.sh

# Copy entrypoint script for log forwarding
COPY --chmod=755 --chown=leo:leo devnet-entrypoint.sh /aleo/devnet-entrypoint.sh

# Set environment variables for better devnet operation
ENV RUST_LOG=info \
    RUST_BACKTRACE=1

# Environment variables for devnet configuration (used by entrypoint)
ENV STORAGE=/aleo/data \
    VERBOSITY=4 \
    NUM_VALIDATORS=4 \
    NUM_CLIENTS=1 \
    CLEAR_STORAGE=no \
    SNARKOS_FEATURES=test_network \
    LOG_WAIT_SECONDS=5 \
    LOG_POLL_INTERVAL=3

# Expose ports
# 3030: REST API
# 4130: Node communication
# 4180: Metrics (if enabled)
EXPOSE 3030 4130 4180

# Volume for blockchain storage (owned by leo user)
VOLUME ["/aleo/data"]

# Default entrypoint uses wrapper script for log forwarding
# The wrapper script:
# - Starts leo devnet in background
# - Tails snarkOS log files to container stdout
# - Handles graceful shutdown signals
ENTRYPOINT ["/aleo/devnet-entrypoint.sh"]

# Default command is empty (wrapper uses environment variables)
# Pass additional arguments to override: docker run ... -- --extra-flag
CMD []

# To bypass the wrapper and use leo directly:
# docker run --entrypoint /usr/local/bin/leo ... devnet --help

# Build metadata
ARG LEO_VERSION
ARG SNARKOS_VERSION
LABEL org.opencontainers.image.title="Aleo Devnet" \
      org.opencontainers.image.description="Leo CLI with snarkOS for local Aleo development network" \
      org.opencontainers.image.documentation="https://developer.aleo.org" \
      leo.version="${LEO_VERSION}" \
      snarkos.version="${SNARKOS_VERSION}" \
      build.features="default,snarkos-node-metrics,test_network"
