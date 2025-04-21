# syntax=docker/dockerfile:1.2

ARG DEBIAN_RELEASE=bookworm
ARG RUST_VERSION=1.85.1

# Stage 1: Build leo-lang from source
FROM rust:${RUST_VERSION}-slim-${DEBIAN_RELEASE} as builder

ARG AMARELEO_VERSION=v2.2.0
ARG AMARELEO_REPO=https://github.com/kaxxa123/amareleo-chain
# Force rust to use external Git instead of the internal libgit wrapper
ENV CARGO_NET_GIT_FETCH_WITH_CLI=true

# Install build dependencies in a single layer
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    clang \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Clone repo and build Leo CLI
RUN git clone -b "${AMARELEO_VERSION}" --recurse-submodules --single-branch --depth 1 "${AMARELEO_REPO}"

WORKDIR /app/amareleo-chain

# Ensure we use the specified Rust version (required by snarkvm)
ARG RUST_VERSION
RUN rustup toolchain install ${RUST_VERSION} --force && rustup default ${RUST_VERSION}

# Compile with optimizations
RUN cargo +${RUST_VERSION} install --path .

# Stage 2: Create final minimal image
FROM debian:${DEBIAN_RELEASE}-slim

# Re-declare the build arg in the final stage to ensure proper variable scope
ARG DEBIAN_RELEASE
ARG AMARELEO_REPO

LABEL org.opencontainers.image.source="${AMARELEO_REPO}"
LABEL org.opencontainers.image.description="Amareleo Chain node"
LABEL org.opencontainers.image.documentation="${AMARELEO_REPO}"

# Copy amareleo-chain binary from the builder stage
COPY --from=builder /usr/local/cargo/bin/amareleo-chain /usr/local/bin/

# Create non-root user for better security
RUN groupadd -r amareleo && useradd -r -g amareleo amareleo

# Create and set permissions for data directory
RUN mkdir -p /data/amareleo && chown -R amareleo:amareleo /data/amareleo

# Set the working directory
WORKDIR /data/amareleo

# Install only required runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl-dev \
    ca-certificates \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Expose ports
EXPOSE 3030 9000

# Switch to non-root user
USER amareleo

# Set the entrypoint to run the node
ENTRYPOINT ["amareleo-chain", "start"]

# Provide default arguments that can be overridden
CMD ["--network", "1", "--verbosity", "1", "--rest", "0.0.0.0:3030", "--storage", "/data/amareleo"]