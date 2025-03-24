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

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    git \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
# Leo CLI
RUN git clone -b "${LEO_VERSION}" --recurse-submodules --single-branch https://github.com/ProvableHQ/leo

WORKDIR /app/leo
# For Mac Silicon this will default to aarch64-unknown-linux-gnu
# Ensure we use the specified Rust version (required by snarkvm)
ARG RUST_VERSION
RUN rustup toolchain install ${RUST_VERSION} --force && rustup default ${RUST_VERSION}
# Use the explicitly set Rust version for compilation
ARG RUST_VERSION
RUN cargo +${RUST_VERSION} install --path .

# Stage 2: Create final image
FROM node:${NODE_VERSION}-${DEBIAN_RELEASE}-slim

# Copy leo-lang binary from the builder stage
COPY --from=builder /usr/local/cargo/bin/leo /usr/local/bin/

# Set path to make leo-lang easily accessible
ENV PATH="/usr/local/bin:${PATH}"

# Install required packages for all images - consolidate into a single layer
ARG INCLUDE_GITHUB_ACTION_TOOLS
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Always install libssl-dev and ca-certificates
    libssl-dev \
    ca-certificates \
    # Conditionally install GitHub Action dependencies
    $(if [ "$INCLUDE_GITHUB_ACTION_TOOLS" = "true" ]; then \
        echo "git git-lfs curl gnupg lsb-release"; \
    fi) \
    && \
    # Always update-ca-certificates
    update-ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    # Conditionally install Docker CLI and Docker Compose
    && if [ "$INCLUDE_GITHUB_ACTION_TOOLS" = "true" ]; then \
        # Install Docker CLI
        mkdir -p /etc/apt/keyrings \
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
        && mkdir -p /github/workspace; \
    fi

# Set appropriate workdir based on the type of image
WORKDIR /app
RUN if [ "$INCLUDE_GITHUB_ACTION_TOOLS" = "true" ]; then \
    # For GitHub Actions image
    cd /github/workspace && \
    echo "WORKDIR=/github/workspace" >> /etc/environment; \
fi

# Add version verification script
RUN echo '#!/bin/sh\n\
echo "Installed tools:"\n\
echo "- Leo: $(leo --version)"\n\
echo "- libssl-dev: $(dpkg-query -W -f='"'${Version}\n'"' libssl-dev)"\n\
if command -v git &> /dev/null; then\n\
    echo "- Git: $(git --version)"\n\
fi\n\
if command -v docker &> /dev/null; then\n\
    echo "- Docker: $(docker --version)"\n\
fi\n\
if [ -x "/usr/local/lib/docker/cli-plugins/docker-compose" ]; then\n\
    echo "- Docker Compose: $(docker compose version)"\n\
fi' > /usr/local/bin/check-versions \
    && chmod +x /usr/local/bin/check-versions

# Default command to show installed versions
CMD ["check-versions"]