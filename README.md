# Aleo Blockchain Docker Images

This repository provides Docker images for Aleo blockchain tooling:

- **Leo Lang Images**: The Leo programming language CLI tool designed for building and running zero-knowledge applications
- **Aleo Devnet Image**: Integrated development environment with Leo v3 and snarkOS for running local test networks

Image variants available:

- **Standard Image**: Contains the core CLI tools with necessary runtime dependencies
- **Devnet Image**: Combined Leo and snarkOS for local blockchain development

All images are multi-architecture, supporting AMD64 and ARM64 platforms.

## 📦 Docker Images

### Pre-built Images

Pre-built images are available on GitHub Container Registry:

#### Leo Lang
- **Standard**: `ghcr.io/sealance-io/leo-lang:v3.5.0`

#### Aleo Devnet
- **Integrated**: `ghcr.io/sealance-io/aleo-devnet:v3.5.0-v4.5.4`

### Custom Deployment Snapshots
- **With deployed programs**: `ghcr.io/sealance-io/aleo-devnet-custom:latest`

You can also use the `latest` tag to always get the most recent version.

### Image Contents

#### Leo Lang Standard Image (`leo-lang`)
- Leo CLI v3.5.0
- Node.js v24
- Debian trixie (slim)
- Essential SSL libraries

#### Aleo Devnet Image (`aleo-devnet`)
- Leo CLI v3.5.0
- snarkOS v4.5.4
- Pre-downloaded mainnet prover parameters (~2GB)
- Debian trixie (slim)
- Essential runtime libraries
- Configured for local development

## 🚀 Usage

### Leo Lang Standard Image

Perfect for development, deployment, and running Leo applications:

```bash
# Run the Leo CLI directly
docker run --rm ghcr.io/sealance-io/leo-lang:v3.5.0 leo --help

# Check installed versions
docker run --rm ghcr.io/sealance-io/leo-lang:v3.5.0

# Mount your project directory and work with Leo
docker run --rm -v $(pwd):/app -w /app ghcr.io/sealance-io/leo-lang:v3.5.0 leo build

# Start a shell in the container
docker run --rm -it -v $(pwd):/app -w /app ghcr.io/sealance-io/leo-lang:v3.5.0 /bin/bash
```

### Aleo Devnet Image

For running a local Aleo development network with Leo v3 and snarkOS:

```bash
# Run a minimal devnet (4 validators + 1 client)
docker run -it --rm -p 3030:3030 -p 4130:4130 \
  -v $(pwd)/data:/aleo/data \
  ghcr.io/sealance-io/aleo-devnet:v3.5.0-v4.5.4

# Run with custom devnet parameters
docker run -it --rm -p 3030:3030 -p 4130:4130 \
  -v $(pwd)/data:/aleo/data \
  ghcr.io/sealance-io/aleo-devnet:v3.5.0-v4.5.4 \
  devnet --storage /aleo/data --clear-storage --yes \
  --verbosity 4 --num-validators 4 --num-clients 2

# Run snarkOS directly instead of Leo devnet command
docker run -it --rm -p 3030:3030 -p 4130:4130 \
  --entrypoint ./snarkos \
  ghcr.io/sealance-io/aleo-devnet:v3.5.0-v4.5.4 \
  start --client --nodisplay --node 0.0.0.0:4130 \
  --network 1 --dev 0 --rest 0.0.0.0:3030

# Access Leo CLI for development
docker run -it --rm -v $(pwd):/app -w /app \
  ghcr.io/sealance-io/aleo-devnet:v3.5.0-v4.5.4 \
  new my_project
```
#### GitHub Actions Example

For CI/CD workflows, use the `setup-leo-action` instead of container images:

```yaml
name: Aleo Project Build and Test

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Leo CLI
        uses: sealance-io/setup-leo-action@126611b39ce92d063c50da6623f8a0b08bf294dd # v1.0.0
        with:
          version: '3.4.0'
          rust-version: '1.92.0'

      - name: Build Leo project
        run: leo build

      - name: Run tests
        run: leo test
```

See [setup-leo-action](https://github.com/sealance-io/setup-leo-action) for more options.

## 📂 Project Structure

The project consists of the following files:

```
.
├── build-publish-image.sh               # Build script for creating and publishing images
├── build-publish-deployment-snapshot.sh # Build script for deployment snapshots
├── leo.Dockerfile                       # Multi-stage Dockerfile for Leo Lang
├── aleo-devnet.Dockerfile               # Multi-stage Dockerfile for Aleo Devnet (Leo + snarkOS)
├── devnet-entrypoint.sh                 # Entrypoint wrapper for aleo-devnet (log forwarding, graceful shutdown)
├── docker-compose.yaml                  # Docker Compose setup for local testnet
├── download-provers.sh                  # Script to download Aleo prover parameters
├── required-programs.txt                # Programs that must exist in every deployment snapshot
└── README.md                            # This documentation file
```

The build script automatically:
- Uses its own directory as the build context
- Supports building different image types with the same script
- Uses Docker BuildKit or Podman to build multi-architecture images
- Targets specific stages in the Dockerfile for different image variants

## 🔄 CI/CD Automation

This repository includes automated workflows for building and publishing images, including:
- Automated version detection and builds for Leo
- Manual build triggers through GitHub Actions
- Deployment snapshot creation for custom Aleo programs

For detailed information about the CI/CD workflows, please see the [CI/CD documentation](./docs/CI.md).

## 🌐 Docker Compose Local Testnet

The `docker-compose.yaml` file sets up a local Aleo testnet with:
- 4 validator nodes (validator0-3)
- 1 client node with REST API
- Fixed IP addressing for consistent peer connections
- REST API exposed on port 3030

To run the local testnet:

```bash
# Start the testnet
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f validator0

# Access REST API
curl http://localhost:3030/testnet/latest/height

# Stop the testnet
docker-compose down
```

## 🔧 Building Images Locally

This repository provides a build script to create both image variants for any supported project.

### Prerequisites

- Docker with buildx plugin OR Podman
- GitHub Container Registry access (if pushing)

### Build Commands

```bash
# Login to GitHub Container Registry (only needed when pushing)
cat ~/.github/token | docker login ghcr.io --username USERNAME --password-stdin

# Build Leo Lang image
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang

# Build Aleo Devnet image (Leo v3 + snarkOS)
./build-publish-image.sh --dockerfile aleo-devnet.Dockerfile --image-name aleo-devnet

# Build without tagging as latest
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang --no-latest

# Build locally without pushing to registry
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang --no-push

# Build only for host architecture (faster development builds)
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang --local-arch

# Local development build (single arch, no push)
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang --local-arch --no-push

# Build with custom variant suffix
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang --variant node24

# Get help
./build-publish-image.sh --help
```

### Building Deployment Snapshots

The repository includes a script to create custom Aleo devnet images with pre-deployed programs:

```bash
# Build deployment snapshot from main branch (without pushing)
./build-publish-deployment-snapshot.sh --commit main --skip-push

# Build from specific branch/tag/commit
./build-publish-deployment-snapshot.sh --commit develop --skip-push
./build-publish-deployment-snapshot.sh --commit v1.0.0 --skip-push
./build-publish-deployment-snapshot.sh --commit abc1234 --skip-push

# Build with custom base image version
./build-publish-deployment-snapshot.sh --version v3.5.0-v4.5.4 --skip-push

# Build and push to registry (requires authentication)
./build-publish-deployment-snapshot.sh --commit main --version v3.5.0-v4.5.4

# Override required programs for verification (default: from required-programs.txt)
./build-publish-deployment-snapshot.sh --commit main --skip-push --required-programs "merkle_tree.aleo,custom.aleo"

# Get help
./build-publish-deployment-snapshot.sh --help
```

This script:
- Clones the compliant-transfer-aleo repository
- Starts a local Aleo devnet container (volume mounted at `/aleo/data` only)
- Deploys programs to the devnet
- Verifies required programs exist via REST API before stopping the container
- Captures only blockchain state (not runtime files) from the container
- Creates a new Docker image with the pre-deployed state
- Runs post-build E2E verification per-platform (amd64 + arm64)
- Retags the verified version-tag digest as `latest` (no rebuild)
- Supports multi-architecture builds (AMD64 and ARM64)
- **Fail-closed**: publish flows require a non-empty program list (from `required-programs.txt` or `--required-programs`)

### Error Recovery

If you encounter errors during pushing:

1. The script automatically retries push operations up to 3 times with a 10-second delay
2. Ensure your GitHub token has proper permissions (packages:write)
3. Check that you're logged in to the registry with `docker login` or `podman login`

## 🏗️ Customizing the Build

### Using the --variant flag

The `--variant` flag allows you to add a suffix to version tags (not `latest`), useful for building specialized versions:

```bash
# Build Leo with Node.js 24
NODE_VERSION=24 ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang --variant node24
# Produces: leo-lang:v3.5.0-node24, leo-lang:latest

# Build with custom Rust version
RUST_VERSION=1.89.0 ./build-publish-image.sh --dockerfile aleo-devnet.Dockerfile --image-name aleo-devnet --variant rust189
# Produces: aleo-devnet:v3.5.0-v4.5.4-rust189, aleo-devnet:latest
```

### Using environment variables

The build process can be customized using environment variables:

```bash
# Override Leo version
LEO_VERSION="v3.5.0" ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang

# Override Leo repository URL
LEO_REPO="https://github.com/your-fork/leo" ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang

# Override Aleo Devnet versions (Leo and snarkOS)
LEO_VERSION="v3.5.0" SNARKOS_VERSION="v4.5.4" ./build-publish-image.sh --dockerfile aleo-devnet.Dockerfile --image-name aleo-devnet

# Override Rust version for Aleo Devnet
RUST_VERSION="1.92.0" ./build-publish-image.sh --dockerfile aleo-devnet.Dockerfile --image-name aleo-devnet

# Override Node.js version (Leo Lang only)
NODE_VERSION=18 ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang

# Override base image distribution
DEBIAN_RELEASE=bullseye ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang

# Override registry
REGISTRY="docker.io" ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang

# Override image name directly (alternative to --image-name)
IMAGE_NAME="custom-leo" ./build-publish-image.sh --dockerfile leo.Dockerfile

# Multiple overrides at once
LEO_VERSION="v3.5.0" LEO_REPO="https://github.com/your-fork/leo" NODE_VERSION=18 ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang
```

## 🛠️ Script Features

The build script includes several features to ensure robust and flexible builds:

- **Strict error handling** with `set -euo pipefail` to catch issues early
- **Cross-platform compatibility** for both Linux and macOS
- **Build context awareness** using the script's directory
- **Multi-image support** for building different image types with the same script
- **Dynamic configuration** via environment variables or command-line options
- **Multi-architecture support** for AMD64 and ARM64
- **Flexible build targets** for local or remote, single or multi-architecture
- **Smart version handling** for different project types
- **Target-based building** using Docker multi-stage builds
- **Repository customization** for building from forks or different sources
- **Variant support** for building specialized versions with custom tag suffixes

## ⚠️ Compatibility Notes

### Docker Version Requirements

The build script works with:

- **Docker**: Version 19.03 or later with buildx plugin
- **Podman**: Version 3.0 or later for full multi-architecture support

If you encounter errors with the Docker build related to heredoc syntax or other advanced Dockerfile features, make sure you're using a recent Docker version or enable BuildKit with:

```bash
export DOCKER_BUILDKIT=1
```

You can also use the compatible Dockerfile that avoids using heredoc syntax for broader compatibility.

## 🔍 Troubleshooting

### Image Not Building for ARM64

Make sure Docker buildx is properly set up:

```bash
docker buildx ls
```

### Authentication Issues with GHCR

Ensure your GitHub token has the necessary package permissions:

```bash
echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin
```

### Permission Issues in Mounted Volumes

Add the appropriate user permissions:

```bash
docker run --rm -v $(pwd):/app -w /app --user $(id -u):$(id -g) ghcr.io/sealance-io/leo-lang:v3.5.0 leo build
```

## 📜 License

This repository is licensed under the Apache License, Version 2.0.
See the [LICENSE](./LICENSE) file for details.
