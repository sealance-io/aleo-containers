#!/usr/bin/env bash

# see: https://danmanners.com/posts/2022-01-buildah-multi-arch/
# see: https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
# Make sure to login via docker/podman CLI using your GitHub PAT with 'packages:write' permissions
# echo $CR_PAT | docker login ghcr.io -u $USER --password-stdin
# cat ~/.github/token | podman login ghcr.io --username $USER --password-stdin

set -e

# Set the required variables
export REGISTRY="ghcr.io"
export USER="sealance-io"
export IMAGE_NAME="leo-lang"
export LEO_VERSION="v2.4.1"
export NODE_VERSION=22
export DEBIAN_RELEASE=bookworm

# Parse command-line arguments
BUILD_STANDARD=true
BUILD_CI=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --standard)
      BUILD_STANDARD=true
      shift
      ;;
    --ci)
      BUILD_CI=true
      shift
      ;;
    --both)
      BUILD_STANDARD=true
      BUILD_CI=true
      shift
      ;;
    --help)
      echo "Usage: $0 [--standard] [--ci] [--both]"
      echo "  --standard  Build standard leo-lang image (default)"
      echo "  --ci        Build leo-lang-ci image with GitHub Actions tools"
      echo "  --both      Build both image variants"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

build_and_push() {
  local include_github_tools=$1
  local image_suffix=$2
  local manifest_name="${IMAGE_NAME}${image_suffix}"
  local full_image_name="${REGISTRY}/${USER}/${IMAGE_NAME}${image_suffix}"
  
  echo "Building ${manifest_name} image..."

  if hash podman 2>/dev/null; then
    echo "Using podman for ${manifest_name}"

    # Create a multi-architecture manifest
    podman manifest create ${manifest_name}

    # Build amd64,arm64 architecture container
    podman build \
      --no-cache \
      --build-arg NODE_VERSION="${NODE_VERSION}" \
      --build-arg DEBIAN_RELEASE="${DEBIAN_RELEASE}" \
      --build-arg LEO_VERSION="${LEO_VERSION}" \
      --build-arg INCLUDE_GITHUB_ACTION_TOOLS="${include_github_tools}" \
      --tag "${full_image_name}:${LEO_VERSION}" \
      --manifest ${manifest_name} \
      --platform=linux/arm64/v8,linux/amd64 \
      - < leo.Dockerfile

    # Push the full manifest, with both CPU Architectures
    podman manifest push --all \
      ${manifest_name} \
      "docker://${full_image_name}:${LEO_VERSION}"

    podman manifest push --all \
      ${manifest_name} \
      "docker://${full_image_name}:latest"
  else
    echo "Using docker for ${manifest_name}"

    # multi-platform build requires using 'docker-container' buildx driver
    docker buildx create --use --name ${manifest_name}-builder 2>/dev/null || docker buildx use ${manifest_name}-builder

    # Build both amd64 and arm64 architecture containers and push
    docker buildx build \
      --no-cache \
      --build-arg NODE_VERSION="${NODE_VERSION}" \
      --build-arg DEBIAN_RELEASE="${DEBIAN_RELEASE}" \
      --build-arg LEO_VERSION="${LEO_VERSION}" \
      --build-arg INCLUDE_GITHUB_ACTION_TOOLS="${include_github_tools}" \
      --platform linux/amd64,linux/arm64 \
      --tag "${full_image_name}:${LEO_VERSION}" \
      --tag "${full_image_name}:latest" \
      --push - < leo.Dockerfile
      
    # Clean up
    docker buildx rm ${manifest_name}-builder
  fi
  
  echo "${manifest_name} build complete!"
}

# Build standard image
if [[ "$BUILD_STANDARD" == "true" ]]; then
  build_and_push "false" ""
fi

# Build CI image
if [[ "$BUILD_CI" == "true" ]]; then
  build_and_push "true" "-ci"
fi

echo "Build and push process completed successfully!"