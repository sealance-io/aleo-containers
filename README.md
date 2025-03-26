# aleo-containers

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
- Docker Compose V2
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

Designed for CI/CD pipelines, especially GitHub Actions and enables docker-in-docker (DinD):

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
# Login to GitHub Container Registry
cat ~/.github/token | docker login ghcr.io --username USERNAME --password-stdin

# Build standard image only
./build-publish-leo.sh --standard

# Build CI image only
./build-publish-leo.sh --ci

# Build both variants
./build-publish-leo.sh --both

# Build without tagging as latest
./build-publish-leo.sh --both --no-latest

# Get help
./build-publish-leo.sh --help
```

## 🏗️ Customizing the Build

The build process can be customized using environment variables:

```bash
# Override Leo version
export LEO_VERSION="v2.4.0"

# Override Node.js version
export NODE_VERSION=20

# Override base image distribution
export DEBIAN_RELEASE=bullseye

# Run the build
./build-publish-leo.sh --both
```

## 📋 Dockerfile Details

The Dockerfile uses a multi-stage build process:

1. **Builder Stage**: 
   - Uses a Rust container to compile Leo from source
   - Installs necessary build dependencies

2. **Final Stage**:
   - Based on Node.js slim image
   - Copies the Leo binary from the builder stage
   - Conditionally installs GitHub Actions tools based on the `INCLUDE_GITHUB_ACTION_TOOLS` build argument

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
