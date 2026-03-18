#!/bin/bash

# Multi-platform container build script with deployment artifact generation
# Supports macOS/Linux with docker/podman
# Builds for both amd64 and arm64 architectures and creates manifest lists
# Validated with shellcheck

# Enable strict mode
set -euo pipefail
IFS=$'\n\t'

# Color codes for better output readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_step() {
    echo -e "${BLUE}[BUILD]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -c, --commit <sha/branch/tag>    Git commit SHA, branch, or tag to clone (default: main)"
    echo "  -v, --version <version>          Version tag for aleo-devnet image (default: v3.5.0-v4.5.4)"
    echo "  -t, --consensus-version <num>    Target consensus version for devnet (default: 13)"
    echo "  --skip-push                      Build images but skip pushing to registry (for testing)"
    echo "  -h, --help                       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                               # Use defaults (main branch, v3.5.0-v4.5.4)"
    echo "  $0 -c develop -v v3.5.0-v4.5.4   # Use develop branch and v3.5.0-v4.5.4 image"
    echo "  $0 --commit abc1234 --version latest"
    echo "  $0 --skip-push                   # Build locally without pushing"
    echo "  $0 -t 15                         # Use consensus version 15"
    echo ""
    echo "Notes:"
    echo "  - Requires either podman or docker installed and running"
    echo "  - With docker and --skip-push, only current platform is built (buildx limitation)"
    echo "  - For local multi-platform builds, use podman"
    echo "  - Consensus heights (0 to consensus-version - 1) are passed to devnet"
    echo "    to accelerate reaching the target consensus version"
    exit 1
}

# Parse command line arguments
GIT_REF="main"
DEVNET_VERSION="v3.5.0-v4.5.4"
CONSENSUS_VERSION=13
SKIP_PUSH=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--commit)
            GIT_REF="$2"
            shift 2
            ;;
        -v|--version)
            DEVNET_VERSION="$2"
            shift 2
            ;;
        -t|--consensus-version)
            CONSENSUS_VERSION="$2"
            shift 2
            ;;
        --skip-push)
            SKIP_PUSH=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Returns 0 (true) if $1 >= $2, 1 (false) otherwise.
# Both arguments must be in X.Y.Z format.
version_gte() {
    local IFS=.
    local -a v1=($1) v2=($2)
    local i
    for i in 0 1 2; do
        if (( ${v1[i]:-0} > ${v2[i]:-0} )); then return 0; fi
        if (( ${v1[i]:-0} < ${v2[i]:-0} )); then return 1; fi
    done
    return 0  # equal
}

# Validate aleo-devnet version against minimum requirements
# Pre-migration images (< v3.5.0-v4.5.4) lack the leo user, breaking --chown=leo:leo
validate_devnet_version() {
    local version="$1"
    local min_leo="3.5.0"
    local min_snarkos="4.5.3"

    # Extract Leo version (first vX.Y.Z) and snarkOS version (second vA.B.C)
    if [[ "$version" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)-v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
        local leo_ver="${BASH_REMATCH[1]}"
        local snarkos_ver="${BASH_REMATCH[2]}"

        if ! version_gte "$leo_ver" "$min_leo"; then
            print_error "Leo version v${leo_ver} is below minimum v${min_leo}."
            print_error "Pre-migration base images lack the rootless 'leo' user and /aleo/data layout."
            exit 1
        fi
        if ! version_gte "$snarkos_ver" "$min_snarkos"; then
            print_error "snarkOS version v${snarkos_ver} is below minimum v${min_snarkos}."
            print_error "Pre-migration base images lack the rootless 'leo' user and /aleo/data layout."
            exit 1
        fi
    else
        print_warning "Version '${version}' does not match expected format vX.Y.Z-vA.B.C."
        print_warning "Cannot validate against minimum requirements — proceeding anyway."
    fi
}

validate_devnet_version "$DEVNET_VERSION"

print_step "Configuration:"
echo "  Git ref: ${GIT_REF}"
echo "  Aleo Devnet version: ${DEVNET_VERSION}"
echo "  Consensus version: ${CONSENSUS_VERSION}"
echo "  Clone method: SSH"
echo "  Skip push: ${SKIP_PUSH}"
echo "  Dockerfile: Will be generated dynamically"
echo ""

# Constants (after argument parsing since they use DEVNET_VERSION)
REPO_URL="git@github.com:sealance-io/compliant-transfer-aleo.git"
REPO_URL_HTTPS="https://github.com/sealance-io/compliant-transfer-aleo"
CLONE_DIR="compliant-transfer-aleo-build"
CONTAINER_NAME="aleo-devnet-${RANDOM}"
VOLUME_NAME="aleo_devnet_state_volume_${RANDOM}"
DEVNET_IMAGE="ghcr.io/sealance-io/aleo-devnet:${DEVNET_VERSION}"
BUILDER_NAME=""

# Detect container tool (prefer podman over docker)
print_step "Detecting container build tool..."
CONTAINER_TOOL=""
if hash podman 2>/dev/null; then
    CONTAINER_TOOL="podman"
    print_success "Found podman - using podman for builds"
elif hash docker 2>/dev/null; then
    CONTAINER_TOOL="docker"
    print_success "Found docker - using docker for builds"
    if [[ "$SKIP_PUSH" == "true" ]]; then
        print_warning "Note: Docker buildx with --skip-push will only build for current platform"
        print_warning "Use podman for local multi-platform builds"
    fi
else
    print_error "Neither podman nor docker found in PATH. Please install either podman or docker."
    exit 1
fi

# Check if container tool is functional
print_step "Checking if ${CONTAINER_TOOL} is functional..."
if ! ${CONTAINER_TOOL} version &> /dev/null; then
    print_error "${CONTAINER_TOOL} is not functioning properly."
    
    if [[ "$CONTAINER_TOOL" == "podman" ]] && [[ "$OSTYPE" == "darwin"* ]]; then
        print_warning "On macOS, ensure podman machine is started: podman machine start"
    elif [[ "$CONTAINER_TOOL" == "docker" ]] && [[ "$OSTYPE" == "darwin"* ]]; then
        print_warning "On macOS, ensure Docker Desktop is running"
    else
        print_warning "Check your ${CONTAINER_TOOL} installation and ensure the service is running."
    fi
    exit 1
fi
print_success "${CONTAINER_TOOL} is functional."

# Check if npm is available
print_step "Checking for npm..."
if ! command -v npm &> /dev/null; then
    print_error "npm is not installed. Please install Node.js and npm."
    exit 1
fi
print_success "npm is available."

# Cleanup function
cleanup() {
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        print_warning "Script failed. Performing cleanup..."
    fi
    
    # Stop and remove container if it exists
    if ${CONTAINER_TOOL} ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        print_step "Cleaning up container ${CONTAINER_NAME}..."
        ${CONTAINER_TOOL} stop --time=10 "${CONTAINER_NAME}" &> /dev/null || true
        ${CONTAINER_TOOL} rm "${CONTAINER_NAME}" &> /dev/null || true
    fi
    
    # Remove volume if it exists and we're in a failure state
    if [[ $exit_code -ne 0 ]] && ${CONTAINER_TOOL} volume ls -q | grep -q "^${VOLUME_NAME}$"; then
        print_step "Cleaning up volume ${VOLUME_NAME}..."
        ${CONTAINER_TOOL} volume rm "${VOLUME_NAME}" &> /dev/null || true
    fi
    
    # Remove generated Dockerfile on failure
    if [[ $exit_code -ne 0 ]] && [[ -f "Dockerfile" ]] && [[ -d "${CLONE_DIR}" ]]; then
        print_step "Cleaning up generated Dockerfile..."
        rm -f Dockerfile
    fi
    
    # Remove clone directory on failure
    if [[ $exit_code -ne 0 ]] && [[ -d "${CLONE_DIR}" ]]; then
        print_step "Cleaning up clone directory..."
        rm -rf "${CLONE_DIR}"
    fi
    
    # Clean up docker buildx builder if we created one
    if [[ -n "${BUILDER_NAME:-}" ]] && [[ "$CONTAINER_TOOL" == "docker" ]]; then
        docker buildx rm "${BUILDER_NAME}" &> /dev/null || true
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Step 1: Clone repository
print_step "Cloning repository ${REPO_URL} (ref: ${GIT_REF})..."
if [[ -d "${CLONE_DIR}" ]]; then
    print_warning "Directory ${CLONE_DIR} already exists. Removing..."
    rm -rf "${CLONE_DIR}"
fi

# Check SSH connectivity first
if ! ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    print_warning "SSH authentication to GitHub may not be configured."
    print_warning "Ensure you have SSH keys set up for GitHub access."
    print_warning "See: https://docs.github.com/en/authentication/connecting-to-github-with-ssh"
fi

git clone --depth 1 --branch "${GIT_REF}" "${REPO_URL}" "${CLONE_DIR}" 2>/dev/null || {
    # If branch clone fails, try as a commit/tag
    git clone "${REPO_URL}" "${CLONE_DIR}" || {
        print_error "Failed to clone repository. Ensure you have SSH access to GitHub."
        exit 1
    }
    cd "${CLONE_DIR}"
    git checkout "${GIT_REF}"
    cd ..
}
print_success "Repository cloned successfully."

# Change to cloned directory
cd "${CLONE_DIR}"

cp ".env.example" ".env"

# Check and use nvm if available and .nvmrc exists
# Note: nvm is typically a shell function, not a command, so we check differently
if [ -f ".nvmrc" ]; then
    print_step "Found .nvmrc file, checking for nvm..."
    
    # Try to load nvm from common locations
    if [ -s "$HOME/.nvm/nvm.sh" ]; then
        print_step "Loading nvm from ~/.nvm/nvm.sh..."
        # shellcheck disable=SC1091
        source "$HOME/.nvm/nvm.sh"
    elif [ -s "/usr/local/opt/nvm/nvm.sh" ]; then
        print_step "Loading nvm from /usr/local/opt/nvm/nvm.sh..."
        # shellcheck disable=SC1091
        source "/usr/local/opt/nvm/nvm.sh"
    fi
    
    # Check if nvm is now available as a function
    if type nvm &> /dev/null; then
        print_step "Switching to Node.js version specified in .nvmrc..."
        nvm use
        print_success "Node.js version switched to: $(node --version)"
    else
        print_warning ".nvmrc file found but nvm could not be loaded."
        print_warning "Using system Node.js version: $(node --version)"
    fi
else
    print_step "No .nvmrc file found, using system Node.js version: $(node --version)"
fi

# Verify npm is still available after potential version switch
if ! command -v npm &> /dev/null; then
    print_error "npm is not available after Node.js version switch."
    exit 1
fi

# Display npm version for debugging
print_step "Using npm version: $(npm --version)"

# Step 2: Pull aleo-devnet image
print_step "Pulling image ${DEVNET_IMAGE}..."
${CONTAINER_TOOL} pull "${DEVNET_IMAGE}"
print_success "Image pulled successfully."

# Step 3: Create volume and run container
print_step "Creating volume ${VOLUME_NAME}..."
${CONTAINER_TOOL} volume create "${VOLUME_NAME}"
print_success "Volume created."

# Generate consensus version heights (0 to CONSENSUS_VERSION - 1)
CONSENSUS_HEIGHTS=$(seq 0 $((CONSENSUS_VERSION - 1)) | tr '\n' ',' | sed 's/,$//')
print_step "Using consensus heights: ${CONSENSUS_HEIGHTS}"

# Step 4: Install dependencies and run deployment
print_step "Installing npm dependencies..."
if ! npm ci --ignore-scripts; then
    print_error "Failed to install npm dependencies."
    exit 1
fi
print_success "Dependencies installed."
print_step "Running post-install scripts..."
if ! npm run postinstall; then
    print_error "Failed to execute post-install script."
    exit 1
fi
print_step "Building @sealance-io/policy-engine-aleo sdk..."
if ! npm run build --workspace=@sealance-io/policy-engine-aleo; then
    print_error "Failed to build @sealance-io/policy-engine-aleo."
    exit 1
fi
print_success "@sealance-io/policy-engine-aleo installed."

# Check if dokojs is available globally
if ! command -v dokojs &> /dev/null; then
    print_warning "dokojs command not found in PATH."
    print_warning "The compile step might fail if dokojs is not installed."
    print_warning "Please ensure dokojs is installed globally via npm."
fi

print_step "Compiling project (rimraf artifacts && dokojs compile)..."
if ! TESTNET_ENDPOINT="https://api.explorer.provable.com/v1" npm run compile; then
    print_error "Compilation failed. Check if dokojs is properly installed."
    exit 1
fi
print_success "Project compiled."

print_step "Starting container ${CONTAINER_NAME}..."
# Explicit devnet args work with both wrapper (passthrough) and pre-wrapper (direct leo) base images.
# --snarkos-features test_network is required for CONSENSUS_VERSION_HEIGHTS support.
if ! ${CONTAINER_TOOL} run -d \
    -p 3030:3030 \
    -v "${VOLUME_NAME}:/aleo" \
    -e CONSENSUS_VERSION_HEIGHTS="${CONSENSUS_HEIGHTS}" \
    --name "${CONTAINER_NAME}" \
    "${DEVNET_IMAGE}" \
    devnet --storage /aleo/data --clear-storage --yes --verbosity 4 \
    --snarkos ./snarkos --num-clients 1 --snarkos-features test_network; then
    print_error "Failed to start container. Port 3030 might be in use or image issue."
    exit 1
fi
print_success "Container started."

# Wait for container to be ready
print_step "Starting container and waiting for initialization..."
sleep 5

# Verify container is running
if ! ${CONTAINER_TOOL} ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    print_error "Container ${CONTAINER_NAME} is not running."
    ${CONTAINER_TOOL} logs "${CONTAINER_NAME}" 2>&1 || true
    exit 1
fi
print_success "Container is running."

# Wait for devnet to reach target consensus version
print_step "Waiting for devnet to reach consensus version >= ${CONSENSUS_VERSION}..."
RETRY_COUNT=0
MAX_RETRIES=100
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    CURRENT_CONSENSUS=$(curl -s "http://localhost:3030/testnet/consensus_version" 2>/dev/null || echo "")
    if [ -n "$CURRENT_CONSENSUS" ] && [ "$CURRENT_CONSENSUS" -ge "$CONSENSUS_VERSION" ] 2>/dev/null; then
        print_success "Devnet consensus version is $CURRENT_CONSENSUS (>= ${CONSENSUS_VERSION})."
        break
    fi
    if [ -z "$CURRENT_CONSENSUS" ]; then
        print_warning "Waiting for consensus version response... (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)"
    else
        print_warning "Current consensus version: $CURRENT_CONSENSUS, waiting for >= ${CONSENSUS_VERSION}... (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)"
    fi
    sleep 5
    RETRY_COUNT=$((RETRY_COUNT + 1))
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    print_error "Devnet did not reach consensus version >= ${CONSENSUS_VERSION} after ${MAX_RETRIES} attempts."
    print_warning "Container logs:"
    ${CONTAINER_TOOL} logs "${CONTAINER_NAME}" --tail 50 || true
    exit 1
fi

print_step "Running deployment to devnet..."
if ! npm run deploy:devnet; then
    print_error "Deployment failed. Check the container logs for details."
    exit 1
fi
print_success "Deployment completed."

# Step 5: Gracefully stop container
print_step "Stopping container ${CONTAINER_NAME} gracefully..."
${CONTAINER_TOOL} stop --time=30 "${CONTAINER_NAME}"
print_success "Container stopped."

# Additional wait to ensure everything is flushed
print_step "Waiting for complete shutdown..."
sleep 30

# Step 6: Copy state from volume to host
print_step "Creating devnet directory..."
mkdir -p "$(pwd)/devnet"

print_step "Copying state from volume to host..."
${CONTAINER_TOOL} run --rm \
    -v "${VOLUME_NAME}:/aleo" \
    -v "$(pwd)/devnet:/backup" \
    alpine sh -c "cp -r /aleo/. /backup/"
print_success "State copied to ./devnet"

# Step 7: Cleanup container (volume is kept for now)
print_step "Removing container ${CONTAINER_NAME}..."
${CONTAINER_TOOL} rm "${CONTAINER_NAME}"
print_success "Container removed."

# Remove the volume as we've extracted the data
print_step "Removing volume ${VOLUME_NAME}..."
${CONTAINER_TOOL} volume rm "${VOLUME_NAME}"
print_success "Volume removed."

print_step "Starting multi-platform container build process..."

# Generate Dockerfile
print_step "Generating Dockerfile..."
cat > Dockerfile << EOF
# syntax=docker/dockerfile:1.2

ARG DEVNET_VERSION=${DEVNET_VERSION}
ARG GIT_COMMIT=""
ARG BUILD_DATE=""
ARG REPO_URL=""

FROM ghcr.io/sealance-io/aleo-devnet:\${DEVNET_VERSION}

# OCI standard labels
LABEL org.opencontainers.image.created="\${BUILD_DATE}"
LABEL org.opencontainers.image.authors="Sealance.io"
LABEL org.opencontainers.image.url="\${REPO_URL}"
LABEL org.opencontainers.image.source="\${REPO_URL}"
LABEL org.opencontainers.image.version="\${DEVNET_VERSION}"
LABEL org.opencontainers.image.revision="\${GIT_COMMIT}"
LABEL org.opencontainers.image.title="Aleo devnet Custom"
LABEL org.opencontainers.image.description="Aleo devnet node with sealance-io programs deployment"
LABEL org.opencontainers.image.base.name="ghcr.io/sealance-io/aleo-devnet:\${DEVNET_VERSION}"

# Copy blockchain state with proper ownership for leo user
COPY --chown=leo:leo ./devnet /aleo
EOF
print_success "Dockerfile generated."

# Display generated Dockerfile
print_step "Generated Dockerfile content:"
echo "----------------------------------------"
cat Dockerfile
echo "----------------------------------------"
echo ""

# Validate remaining prerequisites
print_step "Validating build prerequisites..."

# Check if ./devnet directory exists and has content
if [ ! -d "./devnet" ]; then
    print_error "./devnet directory not found. This should have been created by the deployment process."
    exit 1
fi

rm -rf "$(pwd)/devnet/snarkos"

if [ -z "$(ls -A ./devnet)" ]; then
    print_error "./devnet directory is empty. Deployment may have failed."
    exit 1
fi

# Check if buildx is available for docker (required for multi-platform builds)
if [[ "$CONTAINER_TOOL" == "docker" ]]; then
    print_step "Checking docker buildx availability..."
    if ! docker buildx version &> /dev/null; then
        print_error "Docker buildx is not available. Multi-platform builds require buildx."
        print_warning "Install buildx or use Docker Desktop which includes it by default."
        print_warning "On Linux, you can install buildx with:"
        print_warning "  docker run --rm --privileged multiarch/qemu-user-static --reset -p yes"
        print_warning "  docker buildx create --use --name multibuilder"
        exit 1
    fi
    
    # Check if a builder is available
    if ! docker buildx ls | grep -q "default.*running"; then
        print_step "Setting up docker buildx builder..."
        # Create and use a buildx builder instance
        BUILDER_NAME="multiplatform-builder-$"
        docker buildx create --name "${BUILDER_NAME}" --use &> /dev/null || true
        docker buildx inspect --bootstrap &> /dev/null
        print_success "Docker buildx builder ready."
    else
        print_success "Docker buildx is available and ready."
    fi
fi

print_success "All build prerequisites validated."

# Generate build metadata from git
print_step "Generating build metadata..."
SHORT_SHA=$(git rev-parse --short=8 HEAD)
GIT_COMMIT=$(git rev-parse HEAD)
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Container image configuration
IMAGE_NAME="ghcr.io/sealance-io/aleo-devnet-custom"
VERSION_TAG="${DEVNET_VERSION}-${SHORT_SHA}"
LATEST_TAG="latest"

# Display build information
echo ""
print_step "Build Configuration:"
echo "  Build Tool: ${CONTAINER_TOOL}"
echo "  Repository: ${REPO_URL_HTTPS}"
echo "  Git Commit: ${GIT_COMMIT}"
echo "  Short SHA: ${SHORT_SHA}"
echo "  Build Date: ${BUILD_DATE}"
echo "  Image Name: ${IMAGE_NAME}"
echo "  Version Tag: ${VERSION_TAG}"
echo "  Latest Tag: ${LATEST_TAG}"
echo ""

# Show files that will be copied (including hidden files)
print_step "Files in ./devnet directory (including hidden files):"
ls -la ./devnet
echo ""

# Function to build and push multi-platform images
build_multiplatform() {
    local tag=$1
    
    if [[ "$CONTAINER_TOOL" == "podman" ]]; then
        # Podman approach: build separately and create manifest
        
        # Clean up any existing manifest lists that might conflict
        print_step "Cleaning up existing manifests..."
        podman manifest rm "${IMAGE_NAME}:${tag}" 2>/dev/null || true
        
        # Build for AMD64 architecture
        print_step "Building container image for linux/amd64..."
        podman build \
          --platform linux/amd64 \
          --build-arg GIT_COMMIT="${GIT_COMMIT}" \
          --build-arg BUILD_DATE="${BUILD_DATE}" \
          --build-arg REPO_URL="${REPO_URL_HTTPS}" \
          --tag "${IMAGE_NAME}:${tag}-amd64" \
          .
        print_success "AMD64 build completed."
        
        # Build for ARM64 architecture  
        print_step "Building container image for linux/arm64..."
        podman build \
          --platform linux/arm64 \
          --build-arg GIT_COMMIT="${GIT_COMMIT}" \
          --build-arg BUILD_DATE="${BUILD_DATE}" \
          --build-arg REPO_URL="${REPO_URL_HTTPS}" \
          --tag "${IMAGE_NAME}:${tag}-arm64" \
          .
        print_success "ARM64 build completed."
        
        # Push individual architecture-specific images
        if [[ "$SKIP_PUSH" == "false" ]]; then
            print_step "Pushing AMD64 image to registry..."
            podman push "${IMAGE_NAME}:${tag}-amd64"
            print_success "AMD64 image pushed."
            
            print_step "Pushing ARM64 image to registry..."
            podman push "${IMAGE_NAME}:${tag}-arm64"
            print_success "ARM64 image pushed."
        else
            print_warning "Skipping push of architecture-specific images (--skip-push was specified)"
        fi
        
        # Create and push manifest list
        print_step "Creating manifest list for ${tag}..."
        podman manifest create "${IMAGE_NAME}:${tag}"
        podman manifest add "${IMAGE_NAME}:${tag}" "${IMAGE_NAME}:${tag}-amd64"
        podman manifest add "${IMAGE_NAME}:${tag}" "${IMAGE_NAME}:${tag}-arm64"
        
        if [[ "$SKIP_PUSH" == "false" ]]; then
            print_step "Pushing manifest list for ${tag}..."
            podman manifest push "${IMAGE_NAME}:${tag}"
            print_success "Manifest list for ${tag} pushed."
        else
            print_warning "Skipping push of manifest list (--skip-push was specified)"
            print_success "Manifest list for ${tag} created locally."
        fi
        
    else
        # Docker buildx approach: build and push in one command
        if [[ "$SKIP_PUSH" == "false" ]]; then
            print_step "Building and pushing multi-platform image for ${tag}..."
            docker buildx build \
              --platform linux/amd64,linux/arm64 \
              --build-arg GIT_COMMIT="${GIT_COMMIT}" \
              --build-arg BUILD_DATE="${BUILD_DATE}" \
              --build-arg REPO_URL="${REPO_URL_HTTPS}" \
              --tag "${IMAGE_NAME}:${tag}" \
              --push \
              .
            print_success "Multi-platform image for ${tag} built and pushed."
        else
            # When skipping push with Docker, we can only build for the current platform
            print_step "Building image for ${tag} (current platform only)..."
            print_warning "Docker buildx limitation: Cannot load multi-platform images locally"
            print_warning "Building for current platform only. Use podman for local multi-platform builds."
            
            # Detect current platform
            CURRENT_PLATFORM=""
            if [[ "$(uname -m)" == "x86_64" ]]; then
                CURRENT_PLATFORM="linux/amd64"
            elif [[ "$(uname -m)" == "arm64" ]] || [[ "$(uname -m)" == "aarch64" ]]; then
                CURRENT_PLATFORM="linux/arm64"
            else
                print_error "Unsupported platform: $(uname -m)"
                exit 1
            fi
            
            print_step "Building for ${CURRENT_PLATFORM}..."
            docker buildx build \
              --platform "${CURRENT_PLATFORM}" \
              --build-arg GIT_COMMIT="${GIT_COMMIT}" \
              --build-arg BUILD_DATE="${BUILD_DATE}" \
              --build-arg REPO_URL="${REPO_URL_HTTPS}" \
              --tag "${IMAGE_NAME}:${tag}" \
              --load \
              .
            print_success "Image for ${tag} built locally (${CURRENT_PLATFORM})."
        fi
    fi
}

# Build and push version-tagged image
print_step "Starting multi-platform build for version ${VERSION_TAG}..."
build_multiplatform "${VERSION_TAG}"

# Build and push latest-tagged image
print_step "Starting multi-platform build for latest tag..."
build_multiplatform "${LATEST_TAG}"

# Cleanup docker buildx builder if we created one
if [[ "$CONTAINER_TOOL" == "docker" ]] && [[ -n "${BUILDER_NAME}" ]]; then
    print_step "Cleaning up docker buildx builder..."
    docker buildx rm "${BUILDER_NAME}" &> /dev/null || true
fi

# Final summary
echo ""
print_success "Complete build and deployment process finished successfully!"
echo ""
echo "Deployment artifacts were generated from:"
echo "  📦 Repository: ${REPO_URL_HTTPS} (${GIT_REF})"
echo "  📦 Base image: ${DEVNET_IMAGE}"
echo ""
if [[ "$SKIP_PUSH" == "false" ]]; then
    echo "Your custom container images are now available at:"
    echo "  📦 ${IMAGE_NAME}:${VERSION_TAG} (multi-arch)"
    echo "  📦 ${IMAGE_NAME}:${LATEST_TAG} (multi-arch)"
else
    echo "Your custom container images were built locally:"
    if [[ "$CONTAINER_TOOL" == "docker" ]]; then
        echo "  📦 ${IMAGE_NAME}:${VERSION_TAG} (current platform only)"
        echo "  📦 ${IMAGE_NAME}:${LATEST_TAG} (current platform only)"
        echo ""
        echo "Note: Docker buildx limitation - only current platform was built locally"
        echo "For local multi-platform builds, use podman instead"
    else
        echo "  📦 ${IMAGE_NAME}:${VERSION_TAG} (multi-arch)"
        echo "  📦 ${IMAGE_NAME}:${LATEST_TAG} (multi-arch)"
    fi
    echo ""
    echo "Note: Images were NOT pushed to registry (--skip-push was used)"
fi
echo ""
if [[ "$SKIP_PUSH" == "false" ]] || [[ "$CONTAINER_TOOL" == "podman" ]]; then
    echo "Each multi-arch image includes:"
    echo "  🏗️  linux/amd64 (x86_64)"
    echo "  🏗️  linux/arm64 (Apple Silicon, ARM servers)"
    echo ""
fi
if [[ "$SKIP_PUSH" == "false" ]]; then
    echo "You can pull and run these images on any compatible platform:"
    echo "  ${CONTAINER_TOOL} pull ${IMAGE_NAME}:${VERSION_TAG}"
    echo "  ${CONTAINER_TOOL} pull ${IMAGE_NAME}:${LATEST_TAG}"
else
    echo "You can run these images locally with:"
    echo "  ${CONTAINER_TOOL} run ${IMAGE_NAME}:${VERSION_TAG}"
    echo "  ${CONTAINER_TOOL} run ${IMAGE_NAME}:${LATEST_TAG}"
fi