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
  local dir
  # Resolve $source until the file is no longer a symlink
  while [ -L "$source" ]; do
    dir="$(cd -P "$(dirname "$source")" && pwd)"
    source="$(readlink "$source")"
    # If $source was a relative symlink, we need to resolve it relative to the path where the symlink file was located
    [[ $source != /* ]] && source="$dir/$source"
  done
  cd -P "$(dirname "$source")" && pwd
}

# Script directory will be used as build context
SCRIPT_DIR=$(get_script_dir)

# Set default values for variables
REGISTRY=${REGISTRY:-"ghcr.io"}
ORG="sealance-io"  # Hardcoded to avoid conflict with $USER env var

# Default build configuration
IMAGE_NAME=${IMAGE_NAME:-"leo-lang"}
DOCKERFILE=${DOCKERFILE:-"leo.Dockerfile"}
PROJECT_VERSION=""  # Will be set based on the image type
PROJECT_REPO=""     # Will be set based on the image type
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
  local arch
  arch=$(uname -m)
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
        if ! curl -s -H "Authorization: Bearer $(docker config inspect --format='{{index .AuthConfigs "'"${REGISTRY}"'" "Auth"}}' ~/.docker/config.json 2>/dev/null || echo "")" \
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
    --dockerfile)
      if [[ $# -gt 1 ]]; then
        DOCKERFILE="$2"
        shift 2
      else
        echo "Error: Missing argument for --dockerfile"
        exit 1
      fi
      ;;
    --image-name)
      if [[ $# -gt 1 ]]; then
        IMAGE_NAME="$2"
        shift 2
      else
        echo "Error: Missing argument for --image-name"
        exit 1
      fi
      ;;
    --help)
      echo "Usage: $0 [--standard] [--ci] [--both] [--no-latest] [--no-push] [--local-arch] [--dockerfile FILE] [--image-name NAME]"
      echo "  --standard       Build standard image (default)"
      echo "  --ci             Build image with GitHub Actions tools (only for leo-lang)"
      echo "  --both           Build both image variants (only for leo-lang)"
      echo "  --no-latest      Don't tag images as 'latest'"
      echo "  --no-push        Build locally only, don't push to registry"
      echo "  --local-arch     Build only for the host architecture ($(detect_arch))"
      echo "  --dockerfile     Specify the Dockerfile to use (default: leo.Dockerfile)"
      echo "  --image-name     Specify the base name for the image (default: leo-lang)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Set project-specific version variables based on image name
if [[ "$IMAGE_NAME" == "leo-lang" ]]; then
  PROJECT_VERSION=${LEO_VERSION:-"v2.5.0"}
  PROJECT_VERSION_ARG="LEO_VERSION"
  PROJECT_REPO=${LEO_REPO:-"https://github.com/ProvableHQ/leo"}
  PROJECT_REPO_ARG="LEO_REPO"
elif [[ "$IMAGE_NAME" == "amareleo-chain" ]]; then
  # Amareleo-chain doesn't support CI image
  if [[ "$BUILD_CI" == "true" ]]; then
    echo "Error: CI image is not available for amareleo-chain"
    echo "Use --standard instead of --ci or --both"
    exit 1
  fi
  
  PROJECT_VERSION=${AMARELEO_VERSION:-"v2.2.0"}
  PROJECT_VERSION_ARG="AMARELEO_VERSION"
  PROJECT_REPO=${AMARELEO_REPO:-"https://github.com/kaxxa123/amareleo-chain"}
  PROJECT_REPO_ARG="AMARELEO_REPO"
else
  echo "Error: Unknown image name: $IMAGE_NAME"
  echo "Please specify a supported image name with --image-name"
  exit 1
fi

echo "Building for $IMAGE_NAME with $DOCKERFILE"
echo "Version: $PROJECT_VERSION"
echo "Repository: $PROJECT_REPO"

# Check registry credentials if we're pushing
check_registry_credentials

build_and_push() {
  local target_stage=$1
  local image_suffix=$2
  local manifest_name="${IMAGE_NAME}${image_suffix}"
  local full_image_name="${REGISTRY}/${ORG}/${IMAGE_NAME}${image_suffix}"
  
  # Determine if we should use target parameter
  local use_target=false
  if [[ "$IMAGE_NAME" == "leo-lang" ]]; then
    use_target=true
    echo "Building ${manifest_name} image with target stage: ${target_stage}..."
  else
    echo "Building ${manifest_name} image..."
  fi
  
  echo "Platforms: $PLATFORMS"
  echo "Push to registry: $([ "$PUSH_IMAGES" == "true" ] && echo "Yes" || echo "No")"

  # Common build arguments for both podman and docker
  local common_build_args=(
    "--build-arg" "${PROJECT_VERSION_ARG}=${PROJECT_VERSION}"
    "--build-arg" "${PROJECT_REPO_ARG}=${PROJECT_REPO}"
    "--build-arg" "DEBIAN_RELEASE=${DEBIAN_RELEASE}"
  )
  
  # Add NODE_VERSION arg only for leo-lang image
  if [[ "$IMAGE_NAME" == "leo-lang" ]]; then
    common_build_args+=("--build-arg" "NODE_VERSION=${NODE_VERSION}")
  fi

  if hash podman 2>/dev/null; then
    echo "Using podman for ${manifest_name}"

    # For single architecture local builds, use regular podman build
    if [[ "$HOST_ARCH_ONLY" == "true" && "$PUSH_IMAGES" == "false" ]]; then
      echo "Building single-arch local image with podman..."
      
      local podman_args=("${common_build_args[@]}")
      if [[ "$use_target" == "true" ]]; then
        podman_args+=("--target" "${target_stage}")
      fi
      
      podman build \
        "${podman_args[@]}" \
        --tag "${full_image_name}:${PROJECT_VERSION}" \
        -f "${SCRIPT_DIR}/${DOCKERFILE}" \
        "${SCRIPT_DIR}"
      
      if [[ "$TAG_LATEST" == "true" ]]; then
        podman tag "${full_image_name}:${PROJECT_VERSION}" "${full_image_name}:latest"
      fi
    else
      # Create a multi-architecture manifest (only if it doesn't exist)
      if ! podman manifest exists "${manifest_name}" &>/dev/null; then
        echo "Creating new manifest: ${manifest_name}"
        podman manifest create "${manifest_name}"
      else
        echo "Using existing manifest: ${manifest_name}"
      fi

      # Split platforms into array for podman
      IFS=',' read -ra PLATFORM_LIST <<< "$PLATFORMS"
      platform_args=()
      for platform in "${PLATFORM_LIST[@]}"; do
        platform_args+=("--platform" "$platform")
      done

      # Build for specified architecture(s)
      local podman_build_args=("${common_build_args[@]}")
      if [[ "$use_target" == "true" ]]; then
        podman_build_args+=("--target" "${target_stage}")
      fi
      
      podman build \
        "${podman_build_args[@]}" \
        --tag "${full_image_name}:${PROJECT_VERSION}" \
        --manifest "${manifest_name}" \
        "${platform_args[@]}" \
        -f "${SCRIPT_DIR}/${DOCKERFILE}" \
        "${SCRIPT_DIR}"

      # Push the version tag if requested
      if [[ "$PUSH_IMAGES" == "true" ]]; then
        echo "Pushing ${full_image_name}:${PROJECT_VERSION}..."
        retry_command podman manifest push --all \
          "${manifest_name}" \
          "docker://${full_image_name}:${PROJECT_VERSION}"

        # Push latest tag if enabled
        if [[ "$TAG_LATEST" == "true" ]]; then
          echo "Tagging and pushing as latest..."
          retry_command podman manifest push --all \
            "${manifest_name}" \
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
    TAGS=("--tag" "${full_image_name}:${PROJECT_VERSION}")
    if [[ "$TAG_LATEST" == "true" ]]; then
      TAGS+=("--tag" "${full_image_name}:latest")
    fi

    # Build both amd64 and arm64 architecture containers and push if requested
    BUILD_ARGS=(
      "${common_build_args[@]}"
      "--platform" "${PLATFORMS}"
      "${TAGS[@]}"
    )
    
    # Only add target for leo-lang
    if [[ "$use_target" == "true" ]]; then
      BUILD_ARGS+=("--target" "${target_stage}")
    fi

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
  if [[ "$IMAGE_NAME" == "leo-lang" ]]; then
    build_and_push "leo" ""
  else
    build_and_push "" ""  # No target for amareleo-chain
  fi
fi

# Build CI image (only for leo-lang)
if [[ "$BUILD_CI" == "true" ]]; then
  # This check is redundant since we already check earlier,
  # but keeping it for clarity and safety
  if [[ "$IMAGE_NAME" == "leo-lang" ]]; then
    build_and_push "leo-ci" "-ci"
  fi
fi

echo "Build and push process completed successfully!"