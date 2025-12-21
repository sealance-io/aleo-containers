# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This repository provides Docker containerization for the Aleo blockchain ecosystem, including Leo Lang (aleo CLI) and integrated devnet environments with snarkOS.

## Essential Commands

### Building Docker Images

```bash
# Leo Lang standard image (with Node.js)
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang --no-push

# Leo Lang CI image (with full Rust toolchain)
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang --ci --no-push

# Both Leo Lang variants
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang --both --no-push

# Aleo Devnet integrated image (Leo + snarkOS)
./build-publish-image.sh --dockerfile aleo-devnet.Dockerfile --image-name aleo-devnet --no-push

# Local development builds (single architecture, faster)
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang --local-arch --no-push
```

### Building Deployment Snapshots

```bash
# Build deployment snapshot for custom branch/commit (without pushing to remote registry)
./build-publish-deployment-snapshot.sh --commit main --skip-push

# Build deployment snapshot with custom versions for leo and snarkos
./build-publish-deployment-snapshot.sh --version v3.4.0-v4.4.0
```

### Running Containers

```bash
# Run Leo Lang CLI
docker run --rm ghcr.io/sealance-io/leo-lang:v3.4.0 leo --help

# Run Aleo devnet (Leo v3 + snarkOS)
docker run -it --rm -p 3030:3030 -p 4130:4130 -v $(pwd)/data:/data ghcr.io/sealance-io/aleo-devnet:v3.4.0-v4.4.0

# Run local testnet with docker-compose (4 validators + 1 client)
docker-compose up -d

# Access REST API after testnet starts
curl http://localhost:3030/testnet/latest/height
```

### Publishing Images (requires GitHub registry login)

```bash
# Login to GitHub Container Registry
echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin

# Build and push with version tagging
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang

# Build without 'latest' tag
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang --no-latest
```

## Architecture & Key Relationships

### Dockerfile Structure

All Dockerfiles use multi-stage builds:

1. **leo.Dockerfile**:
   - Stage 0 (`planner`): Generates cargo-chef recipe for dependency caching
   - Stage 1 (`builder`): Compiles Leo from source using Rust with cached dependencies
   - Stage 2 (`leo`): Minimal runtime with Node.js, non-root user
   - Stage 3 (`leo-ci`): Full CI environment with Rust, Docker, Git

2. **aleo-devnet.Dockerfile**:
   - Stage 0 (`snarkos-planner`): Generates cargo-chef recipe for snarkOS dependency caching
   - Stage 1 (`snarkos-builder`): Builds snarkOS with test_network feature and cached dependencies
   - Stage 2 (final): Copies Leo from pre-built `leo-lang` image, adds snarkOS and pre-downloaded provers

### Critical Implementation Details

**Prover Downloads**: The `download-provers.sh` script downloads mainnet parameter files (~2GB) to `/.aleo/resources/`. These are required for zero-knowledge proof generation and are pre-cached in images to avoid runtime downloads. Downloads run in parallel (4 at a time) for speed.

**Version Dependencies**:
- Leo v3.4.0+ and aleo-devnet: Rust 1.90.0
- snarkOS: Built with features `default,snarkos-node-metrics,test_network`

**Docker Compose Network**: Uses fixed IP addressing (172.20.0.0/16) with:
- validator0: 172.20.0.2 (verbose logging, REST disabled)
- validator1-3: 172.20.0.3-5 (quiet logging)
- client0: 172.20.0.6 (REST API on port 3030)

### Build Script Intelligence

The `build-publish-image.sh` script:
- Auto-detects Docker vs Podman
- Sets up multi-arch builders dynamically (linux/amd64, linux/arm64)
- Handles version-specific build arguments based on image name
- Retries failed pushes up to 3 times with 10-second delays
- Uses script directory as build context (important for COPY commands)
- Supports `--variant` flag for custom tag suffixes

The `build-publish-deployment-snapshot.sh` script:
- Creates deployment-ready snapshots of custom Aleo programs
- Clones `sealance-io/compliant-transfer-aleo` at specified commit/branch
- Starts devnet container, waits for initialization (credits.aleo available, consensus >= 12)
- Deploys programs then captures blockchain state
- Builds multi-arch images with the pre-deployed state

### Environment Variables for Customization

```bash
# Override versions (defaults shown)
LEO_VERSION="v3.4.0" ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang
LEO_VERSION="v3.4.0" SNARKOS_VERSION="v4.4.0" ./build-publish-image.sh --dockerfile aleo-devnet.Dockerfile --image-name aleo-devnet

# Override repositories (for forks)
LEO_REPO="https://github.com/your-fork/leo" ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang

# Other overrides
NODE_VERSION=18 DEBIAN_RELEASE=bullseye ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang
RUST_VERSION=1.90.0 ./build-publish-image.sh --dockerfile aleo-devnet.Dockerfile --image-name aleo-devnet
```

## CI/CD Automation

GitHub Actions workflows handle automated builds:
- **Weekly version detection**: Scans upstream Leo and snarkOS repos for new releases
- **Reusable build workflow**: `build-publish-image.yml` handles multi-arch builds
- **Manual build workflow**: `manual-build.yml` provides `workflow_dispatch` entry point
- **Deployment snapshots**: `build-publish-deployment-snapshot.yml` creates pre-deployed devnet images

Manual builds can be triggered via GitHub Actions interface or `gh workflow run manual-build.yml`.

### Build Optimizations

The CI pipeline is optimized for Rust compilation speed:

| Optimization | Benefit |
|--------------|---------|
| **Native ARM64 runners** (`ubuntu-24.04-arm`) | Avoids QEMU emulation (10-20x slower) |
| **Parallel matrix builds** | AMD64 and ARM64 build simultaneously |
| **Cargo-chef in Dockerfiles** | Caches compiled dependencies between builds |
| **Registry-based caching** | Stores layers in GHCR (no 10GB GHA cache limit) |
| **Push-by-digest + merge** | Parallel builds → manifest merge |

Build time improvement: **4-6 hours → ~45-50 minutes**

See [docs/CI.md](docs/CI.md) for detailed documentation.