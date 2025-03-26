#!/usr/bin/env bash

# see: https://danmanners.com/posts/2022-01-buildah-multi-arch/
# see: https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry

set -e

# Set your manifest name
export MANIFEST_NAME="leo-lang"

# Set the required variables
export REGISTRY="ghcr.io"
export USER="sealance-io"
export IMAGE_NAME="leo-lang"
export LEO_VERSION="v2.4.1"
export NODE_VERSION=22
export DEBIAN_RELEASE=bookworm

echo "NODE_VERSION is $NODE_VERSION"

# Make sure to login via docker/podman CLI using your GitHub PAT with 'packages:write' permissions
# echo $CR_PAT | docker login ghcr.io -u $USER --password-stdin
# cat ~/.github/token | podman login ghcr.io --username $USER --password-stdin

if hash podman 2>/dev/null; then
    echo "using podman"

    # Create a multi-architecture manifest
    podman manifest create ${MANIFEST_NAME}

    # Build amd64,arm64 architecture container
    podman build \
        --no-cache \
        --build-arg NODE_VERSION="${NODE_VERSION}" \
        --build-arg DEBIAN_RELEASE="${DEBIAN_RELEASE}" \
        --build-arg LEO_VERSION="${LEO_VERSION}" \
        --tag "${REGISTRY}/${USER}/${IMAGE_NAME}:${LEO_VERSION}" \
        --manifest ${MANIFEST_NAME} \
        --platform=linux/arm64/v8,linux/amd64 \
        - < leo.Dockerfile

    # Push the full manifest, with both CPU Architectures
    podman manifest push --all \
        ${MANIFEST_NAME} \
        "docker://${REGISTRY}/${USER}/${IMAGE_NAME}:${LEO_VERSION}"

    podman manifest push --all \
        ${MANIFEST_NAME} \
        "docker://${REGISTRY}/${USER}/${IMAGE_NAME}:latest"
else
    echo "using docker"

    # multi-platform build requires using 'docker-container' buildx driver
    docker buildx create --use

    # Build both amd64 and arm64 architecure containers and push
    docker buildx build \
        --no-cache \
        --build-arg NODE_VERSION="${NODE_VERSION}" \
        --build-arg DEBIAN_RELEASE="${DEBIAN_RELEASE}" \
        --build-arg LEO_VERSION="${LEO_VERSION}" \
        --platform linux/amd64,linux/arm64 \
        --tag "${REGISTRY}/${USER}/${IMAGE_NAME}:${LEO_VERSION}" \
        --push - < leo.Dockerfile
fi