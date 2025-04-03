#!/usr/bin/env bash

# see: https://danmanners.com/posts/2022-01-buildah-multi-arch/
# see: https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
# Make sure to login via docker/podman CLI using your GitHub PAT with 'packages:write' permissions
# echo $CR_PAT | docker login ghcr.io -u $USERNAME --password-stdin
# cat ~/.github/token | podman login ghcr.io --username $USERNAME --password-stdin

# Strict mode:
# -e: Exit immediately if a command exits with non-zero status
# -u: Treat unset variables as an error
# -o pipefail: Return value of a pipeline is the value of the last command to exit with non-zero status
set -euo pipefail

# Get script directory (works on both Linux and macOS)
get_script_dir() {
  local source="${BASH_SOURCE[0]}"
  # Resolve $source until the file is no longer a symlink
  while [ -L "$source" ]; do
    local dir="$(cd -P "$(dirname "$source")" && pwd)"
    source="$(readlink "$source")"
    # If $source was a relative symlink, we need to resolve it relative to the path where the symlink file was located
    [[ $source != /* ]] && source="$dir/$source"
  done
  echo "$(cd -P "$(dirname "$source")" && pwd)"
}

# Script directory will be used as build context
SCRIPT_DIR=$(get_script_dir)
DOCKERFILE="leo.Dockerfile"

# Set values for variables
REGISTRY=${REGISTRY:-"ghcr.io"}
ORG="sealance-io"  # Hardcoded to avoid conflict with $USER env var
IMAGE_NAME=${IMAGE_NAME:-"leo-lang"}
LEO_VERSION=${LEO_VERSION:-"v2.4.1"}
NODE_VERSION=${NODE_VERSION:-22}
DEBIAN_RELEASE=${DEBIAN_RELEASE:-"bookworm"}

# Hardcoded retry settings
MAX_RETRIES=3
RETRY_DELAY=10

# Parse command-line arguments
BUILD_STANDARD=true
BUILD_CI=false
TAG_LATEST=true
PUSH_IMAGES=true
HOST_ARCH_ONLY=false

# Get host architecture
detect_arch() {
  local arch=$(uname -m)
  case "$arch" in
    x86_64)
      echo "linux/amd64"
      ;;
    aarch64|arm64)
      echo "linux/arm64"
      ;;
    *)
      echo "Unsupported architecture: $arch" >&2
      exit 1
      ;;
  esac
}

HOST_PLATFORM=$(detect_arch)
PLATFORMS="linux/amd64,linux/arm64"

# Function to check if registry credentials are valid
check_registry_credentials() {
  if [[ "$PUSH_IMAGES" == "true" ]]; then
    echo "Checking registry credentials..."
    
    if hash podman 2>/dev/null; then
      if ! podman login --get-login "${REGISTRY}" &>/dev/null; then
        echo "Warning: Not logged in to ${REGISTRY}. Image pushing will likely fail."
        echo "Please run: podman login ${REGISTRY} --username <USERNAME>"
        echo "Continuing anyway..."
      fi
    else
      if ! docker login --get-login "${REGISTRY}" &>/dev/null 2>&1; then
        # Docker doesn't have a simple way to check login status, try a minimal API call
        if ! curl -s -H "Authorization: Bearer $(docker config inspect --format='{{index .AuthConfigs "'${REGISTRY}'" "Auth"}}' ~/.docker/config.json 2>/dev/null || echo "")" \
            "https://${REGISTRY}/v2/" | grep -q "Docker Registry API"; then
          echo "Warning: Not logged in to ${REGISTRY}. Image pushing will likely fail."
          echo "Please run: docker login ${REGISTRY} -u <USERNAME>"
          echo "Continuing anyway..."
        fi
      fi
    fi
  fi
}

# Function to retry command on failure
retry_command() {
  local cmd=("$@")
  local retry_count=0
  local return_code=0
  
  while [[ "$retry_count" -lt "$MAX_RETRIES" ]]; do
    if [[ "$retry_count" -gt 0 ]]; then
      echo "Retry attempt $retry_count of $MAX_RETRIES after $RETRY_DELAY seconds..."
      sleep "$RETRY_DELAY"
    fi
    
    "${cmd[@]}" && return 0 || return_code=$?
    
    retry_count=$((retry_count + 1))
    
    if [[ "$retry_count" -lt "$MAX_RETRIES" ]]; then
      echo "Command failed with exit code $return_code. Retrying..."
    else
      echo "Command failed with exit code $return_code after $MAX_RETRIES attempts."
      return $return_code
    fi
  done
  
  return $return_code
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --standard)
      BUILD_STANDARD=true
      BUILD_CI=false
      shift
      ;;
    --ci)
      BUILD_STANDARD=false
      BUILD_CI=true
      shift
      ;;
    --both)
      BUILD_STANDARD=true
      BUILD_CI=true
      shift
      ;;
    --no-latest)
      TAG_LATEST=false
      shift
      ;;
    --no-push)
      PUSH_IMAGES=false
      shift
      ;;
    --local-arch)
      HOST_ARCH_ONLY=true
      PLATFORMS="$HOST_PLATFORM"
      echo "Building only for host architecture: $HOST_PLATFORM"
      shift
      ;;
    --help)
      echo "Usage: $0 [--standard] [--ci] [--both] [--no-latest] [--no-push] [--local-arch]"
      echo "  --standard     Build standard leo-lang image (default)"
      echo "  --ci           Build leo-lang-ci image with GitHub Actions tools"
      echo "  --both         Build both image variants"
      echo "  --no-latest    Don't tag images as 'latest'"
      echo "  --no-push      Build locally only, don't push to registry"
      echo "  --local-arch   Build only for the host architecture ($(detect_arch))"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Check registry credentials if we're pushing
check_registry_credentials

build_and_push() {
  local include_github_tools=$1
  local image_suffix=$2
  local manifest_name="${IMAGE_NAME}${image_suffix}"
  local full_image_name="${REGISTRY}/${ORG}/${IMAGE_NAME}${image_suffix}"
  
  echo "Building ${manifest_name} image..."
  echo "Platforms: $PLATFORMS"
  echo "Push to registry: $([ "$PUSH_IMAGES" == "true" ] && echo "Yes" || echo "No")"

  if hash podman 2>/dev/null; then
    echo "Using podman for ${manifest_name}"

    # For single architecture local builds, use regular podman build
    if [[ "$HOST_ARCH_ONLY" == "true" && "$PUSH_IMAGES" == "false" ]]; then
      echo "Building single-arch local image with podman..."
      
      podman build \
        --build-arg NODE_VERSION="${NODE_VERSION}" \
        --build-arg DEBIAN_RELEASE="${DEBIAN_RELEASE}" \
        --build-arg LEO_VERSION="${LEO_VERSION}" \
        --build-arg INCLUDE_GITHUB_ACTION_TOOLS="${include_github_tools}" \
        --tag "${full_image_name}:${LEO_VERSION}" \
        -f "${SCRIPT_DIR}/${DOCKERFILE}" \
        "${SCRIPT_DIR}"
      
      if [[ "$TAG_LATEST" == "true" ]]; then
        podman tag "${full_image_name}:${LEO_VERSION}" "${full_image_name}:latest"
      fi
    else
      # Create a multi-architecture manifest (only if it doesn't exist)
      if ! podman manifest exists ${manifest_name} &>/dev/null; then
        echo "Creating new manifest: ${manifest_name}"
        podman manifest create ${manifest_name}
      else
        echo "Using existing manifest: ${manifest_name}"
      fi

      # Split platforms into array for podman
      IFS=',' read -ra PLATFORM_ARRAY <<< "$PLATFORMS"
      PLATFORM_ARGS=""
      for platform in "${PLATFORM_ARRAY[@]}"; do
        PLATFORM_ARGS+=" --platform=${platform}"
      done

      # Build for specified architecture(s)
      podman build \
        --build-arg NODE_VERSION="${NODE_VERSION}" \
        --build-arg DEBIAN_RELEASE="${DEBIAN_RELEASE}" \
        --build-arg LEO_VERSION="${LEO_VERSION}" \
        --build-arg INCLUDE_GITHUB_ACTION_TOOLS="${include_github_tools}" \
        --tag "${full_image_name}:${LEO_VERSION}" \
        --manifest ${manifest_name} \
        ${PLATFORM_ARGS} \
        -f "${SCRIPT_DIR}/${DOCKERFILE}" \
        "${SCRIPT_DIR}"

      # Push the version tag if requested
      if [[ "$PUSH_IMAGES" == "true" ]]; then
        echo "Pushing ${full_image_name}:${LEO_VERSION}..."
        retry_command podman manifest push --all \
          ${manifest_name} \
          "docker://${full_image_name}:${LEO_VERSION}"

        # Push latest tag if enabled
        if [[ "$TAG_LATEST" == "true" ]]; then
          echo "Tagging and pushing as latest..."
          retry_command podman manifest push --all \
            ${manifest_name} \
            "docker://${full_image_name}:latest"
        fi
      else
        echo "Skipping push to registry (--no-push specified)"
      fi
    fi
  else
    echo "Using docker for ${manifest_name}"

    # Check if Docker has buildx plugin available
    if ! docker buildx version &>/dev/null; then
      echo "Error: Docker buildx plugin not available. Please install Docker with buildx support."
      exit 1
    fi

    # Create or use existing builder instance
    BUILDER_NAME="${manifest_name}-builder"
    if ! docker buildx inspect "${BUILDER_NAME}" &>/dev/null; then
      docker buildx create --name "${BUILDER_NAME}" --use
    else
      docker buildx use "${BUILDER_NAME}"
    fi

    # Set up tags based on whether latest is enabled
    TAGS=("--tag" "${full_image_name}:${LEO_VERSION}")
    if [[ "$TAG_LATEST" == "true" ]]; then
      TAGS+=("--tag" "${full_image_name}:latest")
    fi

    # Build both amd64 and arm64 architecture containers and push if requested
    BUILD_ARGS=(
      "--build-arg" "NODE_VERSION=${NODE_VERSION}"
      "--build-arg" "DEBIAN_RELEASE=${DEBIAN_RELEASE}"
      "--build-arg" "LEO_VERSION=${LEO_VERSION}"
      "--build-arg" "INCLUDE_GITHUB_ACTION_TOOLS=${include_github_tools}"
      "--platform" "${PLATFORMS}"
      "${TAGS[@]}"
    )

    # Add output type based on push flag
    if [[ "$PUSH_IMAGES" == "true" ]]; then
      BUILD_ARGS+=("--push")
      # Use retry for the build command if pushing
      retry_command docker buildx build "${BUILD_ARGS[@]}" -f "${SCRIPT_DIR}/${DOCKERFILE}" "${SCRIPT_DIR}"
    else
      # Use load for single arch, or output local for multi-arch without push
      if [[ "$HOST_ARCH_ONLY" == "true" ]]; then
        BUILD_ARGS+=("--load")
        docker buildx build "${BUILD_ARGS[@]}" -f "${SCRIPT_DIR}/${DOCKERFILE}" "${SCRIPT_DIR}"
      else
        # For multi-arch builds without push, we need to specify a local output directory
        OUTPUT_DIR=$(mktemp -d)
        BUILD_ARGS+=("--output" "type=local,dest=${OUTPUT_DIR}")
        echo "Building to local directory: ${OUTPUT_DIR}"
        docker buildx build "${BUILD_ARGS[@]}" -f "${SCRIPT_DIR}/${DOCKERFILE}" "${SCRIPT_DIR}"
      fi
    fi
      
    # Don't remove the builder on macOS (to avoid issues with Docker Desktop)
    if [[ "$(uname)" != "Darwin" ]]; then
      docker buildx rm "${BUILDER_NAME}" || true
    fi
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