# aleo-containers

## 📂 Project Structure

The project consists of the following files:

```
.
├── build-publish-leo.sh  # Build script for creating and publishing images
├── leo.Dockerfile        # Multi-stage Dockerfile with non-standard name
└── README.md            # This documentation file
```

The build script automatically:
- Uses its own directory as the build context
- References the Dockerfile using its non-standard name "leo.Dockerfile"
- Supports both standard and CI image variants from the same Dockerfile# Leo Lang Docker Images

This repository provides Docker images with the Leo programming language CLI tool, designed for building and running zero-knowledge applications. The images are available in two variants:

- **Standard Image (`leo-lang`)**: Contains the Leo CLI tool with a Node.js environment
- **CI Image (`leo-lang-ci`)**: Extended version with additional tools for CI/CD pipelines and GitHub Actions workflows

Both images are multi-architecture, supporting AMD64 and ARM64 platforms.

## 📦 Docker Images

### Pre-built Images

Pre-built images are available on GitHub Container Registry:

- **Standard**: `ghcr.io/sealance-io/leo-lang:v2.4.1`
- **CI**: `ghcr.io/sealance-io/leo-lang-ci:v2.4.1`

You can also use the `latest` tag to always get the most recent version.

### Image Contents

#### Standard Image (`leo-lang`)

- Leo CLI v2.4.1
- Node.js v22
- Debian Bookworm (slim)
- Essential SSL libraries

#### CI Image (`leo-lang-ci`)

All components from the standard image, plus:

- Git + Git LFS
- Docker CLI
- Docker Compose
- Additional utilities for CI environments

## 🚀 Usage

### Standard Image

Perfect for development, deployment, and running Leo applications:

```bash
# Run the Leo CLI directly
docker run --rm ghcr.io/sealance-io/leo-lang:v2.4.1 leo --help

# Check installed versions
docker run --rm ghcr.io/sealance-io/leo-lang:v2.4.1

# Mount your project directory and work with Leo
docker run --rm -v $(pwd):/app -w /app ghcr.io/sealance-io/leo-lang:v2.4.1 leo build

# Start a shell in the container
docker run --rm -it -v $(pwd):/app -w /app ghcr.io/sealance-io/leo-lang:v2.4.1 /bin/bash
```

### CI Image

Designed for CI/CD pipelines, especially GitHub Actions:

```bash
# Use with GitHub Actions
steps:
  - name: Build with Leo
    uses: docker://ghcr.io/sealance-io/leo-lang-ci:v2.4.1
    with:
      args: 'leo build'

# Example: Running a pipeline with Docker-in-Docker
docker run --rm \
  -v $(pwd):/github/workspace \
  -v /var/run/docker.sock:/var/run/docker.sock \
  ghcr.io/sealance-io/leo-lang-ci:v2.4.1 \
  bash -c "cd /github/workspace && leo build && docker-compose up -d"
```

#### GitHub Actions Example

```yaml
name: Leo Build and Test

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/sealance-io/leo-lang-ci:v2.4.1
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Build Leo project
        run: leo build
      
      - name: Run tests
        run: leo test
```

## 🔧 Building Images Locally

This repository provides a build script to create both image variants.

### Prerequisites

- Docker with buildx plugin OR Podman
- GitHub Container Registry access (if pushing)

### Build Commands

```bash
# Login to GitHub Container Registry (only needed when pushing)
cat ~/.github/token | docker login ghcr.io --username USERNAME --password-stdin

# Build standard image only
./build-publish-leo.sh --standard

# Build CI image only
./build-publish-leo.sh --ci

# Build both variants
./build-publish-leo.sh --both

# Build without tagging as latest
./build-publish-leo.sh --both --no-latest

# Build locally without pushing to registry
./build-publish-leo.sh --no-push

# Build only for host architecture (faster development builds)
./build-publish-leo.sh --local-arch

# Local development build (single arch, no push)
./build-publish-leo.sh --local-arch --no-push

# Get help
./build-publish-leo.sh --help
```

## 🏗️ Customizing the Build

The build process can be customized using environment variables:

```bash
# Override Leo version
LEO_VERSION="v2.4.0" ./build-publish-leo.sh --both

# Override Node.js version
NODE_VERSION=18 ./build-publish-leo.sh --both

# Override base image distribution
DEBIAN_RELEASE=bullseye ./build-publish-leo.sh --both

# Override registry and organization
REGISTRY="docker.io" USER="yourusername" ./build-publish-leo.sh --both

# Multiple overrides at once
LEO_VERSION="v2.4.0" NODE_VERSION=18 DEBIAN_RELEASE=bullseye ./build-publish-leo.sh --both
```

### Available Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `REGISTRY` | ghcr.io | Container registry to push images to |
| `USER` | sealance-io | Organization/username for the registry |
| `IMAGE_NAME` | leo-lang | Base name for the images |
| `LEO_VERSION` | v2.4.1 | Version of Leo to install |
| `NODE_VERSION` | 22 | Node.js major version |
| `DEBIAN_RELEASE` | bookworm | Debian release to use as base |

## 🛠️ Script Features

The build script includes several features to ensure robust and flexible builds:

- **Strict error handling** with `set -euo pipefail` to catch issues early
- **Cross-platform compatibility** for both Linux and macOS
- **Build context awareness** using the script's directory
- **Non-standard Dockerfile support** using explicit -f flag
- **Dynamic configuration** via environment variables or command-line options
- **Multi-architecture support** for AMD64 and ARM64
- **Flexible build targets** for local or remote, single or multi-architecture

## 🔍 Troubleshooting

### Image Not Building for ARM64

Make sure Docker buildx is properly set up:

```bash
docker buildx ls
```

### Authentication Issues with GHCR

Ensure your GitHub token has the necessary package permissions:

```bash
echo $GITHUB_TOKEN | docker login ghcr.io -u $USERNAME --password-stdin
```

### Permission Issues in Mounted Volumes

Add the appropriate user permissions:

```bash
docker run --rm -v $(pwd):/app -w /app --user $(id -u):$(id -g) ghcr.io/sealance-io/leo-lang:v2.4.1 leo build
```

## 📜 License

TBD
