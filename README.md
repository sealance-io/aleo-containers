# Aleo Blockchain Docker Images

This repository provides Docker images for Aleo blockchain tooling:

- **Leo Lang Images**: The Leo programming language CLI tool designed for building and running zero-knowledge applications
- **Amareleo Chain Images**: The Amareleo blockchain node implementation

Each image is available in two variants:

- **Standard Image**: Contains the core CLI tools with necessary runtime dependencies
- **CI Image**: Extended version with additional tools for CI/CD pipelines and GitHub Actions workflows

All images are multi-architecture, supporting AMD64 and ARM64 platforms.

## 📦 Docker Images

### Pre-built Images

Pre-built images are available on GitHub Container Registry:

#### Leo Lang
- **Standard**: `ghcr.io/sealance-io/leo-lang:v2.5.0`
- **CI**: `ghcr.io/sealance-io/leo-lang-ci:v2.5.0`

#### Amareleo Chain
- **Standard**: `ghcr.io/sealance-io/amareleo-chain:v2.2.0`

You can also use the `latest` tag to always get the most recent version.

### Image Contents

#### Leo Lang Standard Image (`leo-lang`)
- Leo CLI v2.5.0
- Node.js v22
- Debian Bookworm (slim)
- Essential SSL libraries

#### Leo Lang CI Image (`leo-lang-ci`)
- Leo CLI v2.5.0
- Full Rust toolchain (v1.85.1)
- Node.js v22
- Git + Git LFS
- Docker CLI
- Docker Compose
- Debian Bookworm (full)
- Development libraries
- GitHub Actions workspace setup

#### Amareleo Chain Standard Image (`amareleo-chain`)
- Amareleo Chain v2.2.0
- Debian Bookworm (slim)
- Essential SSL libraries
- Running as non-root user

## 🚀 Usage

### Leo Lang Standard Image

Perfect for development, deployment, and running Leo applications:

```bash
# Run the Leo CLI directly
docker run --rm ghcr.io/sealance-io/leo-lang:v2.5.0 leo --help

# Check installed versions
docker run --rm ghcr.io/sealance-io/leo-lang:v2.5.0

# Mount your project directory and work with Leo
docker run --rm -v $(pwd):/app -w /app ghcr.io/sealance-io/leo-lang:v2.5.0 leo build

# Start a shell in the container
docker run --rm -it -v $(pwd):/app -w /app ghcr.io/sealance-io/leo-lang:v2.5.0 /bin/bash
```

### Leo Lang CI Image

Designed for CI/CD pipelines, especially GitHub Actions:

```bash
# Use with GitHub Actions
steps:
  - name: Build with Leo
    uses: docker://ghcr.io/sealance-io/leo-lang-ci:v2.5.0
    with:
      args: 'leo build'

# Example: Running a pipeline with Docker-in-Docker
docker run --rm \
  -v $(pwd):/github/workspace \
  -v /var/run/docker.sock:/var/run/docker.sock \
  ghcr.io/sealance-io/leo-lang-ci:v2.5.0 \
  bash -c "cd /github/workspace && leo build && docker-compose up -d"

# Using the full Rust toolchain in the CI image
docker run --rm -it \
  -v $(pwd):/app \
  ghcr.io/sealance-io/leo-lang-ci:v2.5.0 \
  bash -c "cd /app && cargo build"
```

### Amareleo Chain Standard Image

For running an Amareleo blockchain node:

```bash
# Run node with default settings
docker run -d -p 3030:3030 -p 9000:9000 \
  -v $(pwd)/data:/data/amareleo \
  ghcr.io/sealance-io/amareleo-chain:v2.2.0

# Run with custom parameters
docker run -d -p 3030:3030 -p 9000:9000 \
  -v $(pwd)/data:/data/amareleo \
  ghcr.io/sealance-io/amareleo-chain:v2.2.0 \
  amareleo-chain start --network 2 --verbosity 2 --rest 0.0.0.0:3030
```
#### GitHub Actions Example

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
    container:
      image: ghcr.io/sealance-io/leo-lang-ci:v2.5.0
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Build Leo project
        run: leo build
      
      - name: Run tests
        run: leo test
```

## 📂 Project Structure

The project consists of the following files:

```
.
├── build-publish-image.sh    # Build script for creating and publishing images
├── leo.Dockerfile            # Multi-stage Dockerfile for Leo Lang
├── amareleo.Dockerfile       # Multi-stage Dockerfile for Amareleo Chain
└── README.md                 # This documentation file
```

The build script automatically:
- Uses its own directory as the build context
- Supports building different image types with the same script
- Uses Docker BuildKit or Podman to build multi-architecture images
- Targets specific stages in the Dockerfile for different image variants

## 🔧 Building Images Locally

This repository provides a build script to create both image variants for any supported project.

### Prerequisites

- Docker with buildx plugin OR Podman
- GitHub Container Registry access (if pushing)

### Build Commands

```bash
# Login to GitHub Container Registry (only needed when pushing)
cat ~/.github/token | docker login ghcr.io --username USERNAME --password-stdin

# Build standard Leo Lang image
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang

# Build CI Leo Lang image
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang --ci

# Build both Leo Lang variants
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang --both

# Build standard Amareleo Chain image
./build-publish-image.sh --dockerfile amareleo.Dockerfile --image-name amareleo-chain

# Build without tagging as latest
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang --both --no-latest

# Build locally without pushing to registry
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang --no-push

# Build only for host architecture (faster development builds)
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang --local-arch

# Local development build (single arch, no push)
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang --local-arch --no-push

# Get help
./build-publish-image.sh --help
```

### Error Recovery

If you encounter errors during pushing:

1. The script automatically retries push operations up to 3 times with a 10-second delay
2. Ensure your GitHub token has proper permissions (packages:write)
3. Check that you're logged in to the registry with `docker login` or `podman login`

## 🏗️ Customizing the Build

The build process can be customized using environment variables:

```bash
# Override Leo version
LEO_VERSION="v2.4.0" ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang

# Override Leo repository URL
LEO_REPO="https://github.com/your-fork/leo" ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang

# Override Amareleo version
AMARELEO_VERSION="v2.0.0" ./build-publish-image.sh --dockerfile amareleo.Dockerfile --image-name amareleo-chain

# Override Amareleo repository URL
AMARELEO_REPO="https://github.com/your-fork/amareleo-chain" ./build-publish-image.sh --dockerfile amareleo.Dockerfile --image-name amareleo-chain

# Override Node.js version (Leo Lang only)
NODE_VERSION=18 ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang

# Override base image distribution
DEBIAN_RELEASE=bullseye ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang

# Override registry
REGISTRY="docker.io" ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang

# Override image name directly (alternative to --image-name)
IMAGE_NAME="custom-leo" ./build-publish-image.sh --dockerfile leo.Dockerfile

# Multiple overrides at once
LEO_VERSION="v2.4.0" LEO_REPO="https://github.com/your-fork/leo" NODE_VERSION=18 ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang
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
docker run --rm -v $(pwd):/app -w /app --user $(id -u):$(id -g) ghcr.io/sealance-io/leo-lang:v2.5.0 leo build
```

## 📜 License

TBD