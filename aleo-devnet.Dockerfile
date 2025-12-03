# aleo-devnet.Dockerfile - Leo CLI with snarkOS for local devnet testing
# Build: docker build -f aleo-devnet.Dockerfile -t aleo-devnet .
# Run: docker run -it --rm -p 3030:3030 -p 4130:4130 -v $(pwd)/data:/data aleo-devnet

# Build arguments
ARG LEO_VERSION=v3.4.0
ARG SNARKOS_VERSION=v4.4.0
ARG RUST_VERSION=1.90.0

# Stage 1: Build Leo CLI
FROM rust:${RUST_VERSION}-trixie AS leo-builder

ARG LEO_VERSION

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    libssl-dev \
    pkg-config \
    patch \
    && rm -rf /var/lib/apt/lists/*

# Clone and build Leo
WORKDIR /build
RUN git clone --branch ${LEO_VERSION} --depth 1 \
    https://github.com/ProvableHQ/leo.git
# Force rust to use external Git instead of the internal libgit wrapper
ENV CARGO_NET_GIT_FETCH_WITH_CLI=true

WORKDIR /build/leo

# Build Leo in release mode with default features from repository
RUN cargo build --release --locked && \
    mv target/release/leo /tmp/leo && \
    strip /tmp/leo

# Stage 2: Build snarkOS
FROM rust:${RUST_VERSION}-trixie AS snarkos-builder

ARG SNARKOS_VERSION

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    clang \
    cmake \
    curl \
	clang \
	gcc \
    lld \
    libssl-dev \
    libcurl4-openssl-dev \
    llvm \
    make \
    pkg-config \
    protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

# Clone and build snarkOS
WORKDIR /build
RUN git clone --branch ${SNARKOS_VERSION} --depth 1 \
    https://github.com/ProvableHQ/snarkOS.git
# Force rust to use external Git instead of the internal libgit wrapper
ENV CARGO_NET_GIT_FETCH_WITH_CLI=true

WORKDIR /build/snarkOS

# Build snarkOS in release mode with specified features
# Using the standard feature set for devnet operation
RUN cargo build --release --locked \
    --features "default,snarkos-node-metrics,test_network" && \
    mv target/release/snarkos /tmp/snarkos && \
    strip /tmp/snarkos

# Stage 3: Final runtime image
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

# Set working directory
WORKDIR /aleo

# Copy binaries from builders
COPY --from=leo-builder /tmp/leo /usr/local/bin/leo
COPY --from=snarkos-builder /tmp/snarkos /aleo/snarkos

# Make binaries executable
RUN chmod +x /usr/local/bin/leo /aleo/snarkos

# Create data directory for blockchain storage
RUN mkdir -p /data

# Verify installations
RUN leo --version && \
    ./snarkos --version

RUN mkdir -p /.aleo

# Copy download-provers.sh and set ownership
COPY download-provers.sh /tmp/

# Run the download-provers script as leo user
RUN DEST_DIR="/.aleo/resources/" /tmp/download-provers.sh

# Set environment variables for better devnet operation
ENV RUST_LOG=info \
    RUST_BACKTRACE=1

# Expose ports
# 3030: REST API
# 4130: Node communication
# 4180: Metrics (if enabled)
EXPOSE 3030 4130 4180

# Volume for logs
VOLUME ["/data"]

# Volume for persistent storage
VOLUME ["/aleo"]

# Default entrypoint is leo
ENTRYPOINT ["/usr/local/bin/leo"]

# Default command runs a minimal devnet
# --storage: Use /data for blockchain storage
# --clear-storage: Clean start each time
# --yes: Auto-confirm prompts (now respected due to patch)
# --verbosity 4: Maximum debug output
# --snarkos: Use our pre-built binary
# --num-clients: Single client for minimal setup
CMD ["devnet", "--storage", "/data", "--clear-storage", "--yes", "--verbosity", "4", "--snarkos", "./snarkos", "--num-clients", "1"]

# Build metadata
ARG LEO_VERSION
ARG SNARKOS_VERSION
LABEL org.opencontainers.image.title="Aleo Devnet" \
      org.opencontainers.image.description="Leo CLI with snarkOS for local Aleo development network" \
      org.opencontainers.image.documentation="https://developer.aleo.org" \
      leo.version="${LEO_VERSION}" \
      snarkos.version="${SNARKOS_VERSION}" \
      build.features="default,snarkos-node-metrics,test_network"