# syntax=docker/dockerfile:1.2

ARG NODE_VERSION=22
ARG DEBIAN_RELEASE=bookworm
ARG RUST_VERSION=1.85.1
# This build-arg controls whether to include GitHub Action tools
ARG INCLUDE_GITHUB_ACTION_TOOLS=false

# Stage 1: Build leo-lang from source
FROM rust:${RUST_VERSION}-slim-${DEBIAN_RELEASE} as builder

ARG LEO_VERSION=v2.4.1
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
RUN git clone -b "${LEO_VERSION}" --recurse-submodules --single-branch --depth 1 https://github.com/ProvableHQ/leo

WORKDIR /app/leo

# Ensure we use the specified Rust version (required by snarkvm)
ARG RUST_VERSION
RUN rustup toolchain install ${RUST_VERSION} --force && rustup default ${RUST_VERSION}

# Compile with optimizations
RUN cargo +${RUST_VERSION} install --path .

# Stage 2: Create final image
FROM node:${NODE_VERSION}-${DEBIAN_RELEASE}-slim

LABEL org.opencontainers.image.source="https://github.com/ProvableHQ/leo"
LABEL org.opencontainers.image.description="Leo CLI with NodeJS environment"

# Copy leo-lang binary from the builder stage
COPY --from=builder /usr/local/cargo/bin/leo /usr/local/bin/

# Set path to make leo-lang easily accessible
ENV PATH="/usr/local/bin:${PATH}"

# Install required packages - common packages first
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl-dev \
    curl \
    ca-certificates \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Conditionally install GitHub Action tools
ARG INCLUDE_GITHUB_ACTION_TOOLS
RUN if [ "$INCLUDE_GITHUB_ACTION_TOOLS" = "true" ]; then \
    # Install Git, Git LFS, and other dependencies
    apt-get update && apt-get install -y --no-install-recommends \
        git git-lfs gnupg lsb-release \
    && rm -rf /var/lib/apt/lists/* \
    # Install Docker CLI
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli \
    && rm -rf /var/lib/apt/lists/* \
    # Install Docker Compose V2
    && mkdir -p /usr/local/lib/docker/cli-plugins \
    && curl -SL https://github.com/docker/compose/releases/download/v2.23.3/docker-compose-linux-$(uname -m) -o /usr/local/lib/docker/cli-plugins/docker-compose \
    && chmod +x /usr/local/lib/docker/cli-plugins/docker-compose \
    # Set up environment for GitHub Actions
    && echo "export DOCKER_BUILDKIT=1" >> /etc/profile \
    && echo "export DOCKER_CLI_EXPERIMENTAL=enabled" >> /etc/profile \
    # Create workspace directory for GitHub Actions
    && mkdir -p /github/workspace \
    && echo "WORKDIR=/github/workspace" >> /etc/environment; \
fi

COPY --chmod=755 download-provers.sh /tmp/
RUN /tmp/download-provers.sh

# Set appropriate workdir
WORKDIR /app
RUN if [ "$INCLUDE_GITHUB_ACTION_TOOLS" = "true" ]; then \
    ln -s /github/workspace /app/workspace; \
fi

# Add version verification script
RUN echo '#!/bin/sh' > /usr/local/bin/check-versions \
    && echo 'echo "Installed tools:"' >> /usr/local/bin/check-versions \
    && echo 'echo "- Leo: $(leo --version)"' >> /usr/local/bin/check-versions \
    && echo 'echo "- Node.js: $(node --version)"' >> /usr/local/bin/check-versions \
    && echo 'echo "- NPM: $(npm --version)"' >> /usr/local/bin/check-versions \
    && echo 'echo "- libssl-dev: $(dpkg-query -W -f='\''${Version}\\n'\'' libssl-dev)"' >> /usr/local/bin/check-versions \
    && echo 'if command -v git &> /dev/null; then' >> /usr/local/bin/check-versions \
    && echo '    echo "- Git: $(git --version)"' >> /usr/local/bin/check-versions \
    && echo 'fi' >> /usr/local/bin/check-versions \
    && echo 'if command -v docker &> /dev/null; then' >> /usr/local/bin/check-versions \
    && echo '    echo "- Docker: $(docker --version)"' >> /usr/local/bin/check-versions \
    && echo 'fi' >> /usr/local/bin/check-versions \
    && echo 'if [ -x "/usr/local/lib/docker/cli-plugins/docker-compose" ]; then' >> /usr/local/bin/check-versions \
    && echo '    echo "- Docker Compose: $(docker compose version)"' >> /usr/local/bin/check-versions \
    && echo 'fi' >> /usr/local/bin/check-versions \
    && chmod +x /usr/local/bin/check-versions

# Add simple healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD leo --version > /dev/null || exit 1

# Default command to show installed versions
CMD ["check-versions"]