# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This repository provides Docker containerization for the Aleo blockchain ecosystem, including Leo Lang (aleo CLI), Amareleo Chain (devnet blockchain single node), and integrated devnet environments.

## Essential Commands

### Building Docker Images

```bash
# Leo Lang standard image (with Node.js)
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang --no-push

# Leo Lang CI image (with full Rust toolchain)
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang --ci --no-push

# Both Leo Lang variants
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang --both --no-push

# Amareleo Chain image
./build-publish-image.sh --dockerfile amareleo.Dockerfile --image-name amareleo-chain --no-push

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
./build-publish-deployment-snapshot.sh --version v3.3.0-v4.2.2
```

### Running Containers

```bash
# Run Leo Lang CLI
docker run --rm ghcr.io/sealance-io/leo-lang:v3.3.0 leo --help

# Run Aleo devnet (Leo v3 + snarkOS)
docker run -it --rm -p 3030:3030 -p 4130:4130 -v $(pwd)/data:/data aleo-devnet

# Run local testnet with docker-compose (4 validators + 1 client)
docker-compose up -d

# Access REST API after testnet starts
curl http://localhost:3030/testnet3/latest/height
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
   - Stage 1 (`builder`): Compiles Leo from source using Rust
   - Stage 2 (`leo`): Minimal runtime with Node.js
   - Stage 3 (`leo-ci`): Full CI environment with Rust, Docker, Git

2. **amareleo.Dockerfile**:
   - Stage 1 (`builder`): Compiles Amareleo Chain from source
   - Stage 2 (final): Minimal runtime for blockchain node

3. **aleo-devnet.Dockerfile**:
   - Stage 1 (`leo-builder`): Builds Leo v3 with devnet patch
   - Stage 2 (`snarkos-builder`): Builds snarkOS v4.2.2
   - Stage 3 (final): Combined runtime with pre-downloaded provers

### Critical Implementation Details

**Leo Devnet Patch**: The aleo-devnet.Dockerfile patches Leo's source at leo/cli/commands/devnet/mod.rs:35-40 to respect the `--yes` flag for non-interactive devnet startup. This is essential for containerized operation.

**Prover Downloads**: The `download-provers.sh` script downloads mainnet/testnet parameter files to `/.aleo/resources/`. These are required for zero-knowledge proof generation and are pre-cached in images to avoid runtime downloads.

**Version Dependencies**:
- Leo v3+ requires Rust 1.88.0 (updated from 1.85.1)
- Leo v3.3.0 and earlier use Rust 1.85.1
- snarkOS v4.2.2 requires specific build features: `default,snarkos-node-metrics,test_network`

**Docker Compose Network**: Uses fixed IP addressing (172.20.0.0/16) with:
- validator0: 172.20.0.2 (verbose logging, REST disabled)
- validator1-3: 172.20.0.3-5 (quiet logging)  
- client0: 172.20.0.6 (REST API on port 3030)

### Build Script Intelligence

The `build-publish-image.sh` script:
- Auto-detects Docker vs Podman
- Sets up multi-arch builders dynamically
- Handles version-specific build arguments based on image name
- Retries failed pushes up to 3 times with 10-second delays
- Uses script directory as build context (important for COPY commands)

The `build-publish-deployment-snapshot.sh` script:
- Creates deployment-ready snapshots of custom Aleo programs
- Supports any custom commit/branch for 'https://github.com/sealance-io/compliant-transfer-aleo'
- Uses Leo CI image with full toolchain for building
- Follows same multi-arch and registry patterns as main build script

### Environment Variables for Customization

```bash
# Override versions
LEO_VERSION="v3.3.0" ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang
AMARELEO_VERSION="v2.5.0" ./build-publish-image.sh --dockerfile amareleo.Dockerfile --image-name amareleo-chain
LEO_VERSION="v3.3.0" SNARKOS_VERSION="v4.2.2" ./build-publish-image.sh --dockerfile aleo-devnet.Dockerfile --image-name aleo-devnet

# Override repositories (for forks)
LEO_REPO="https://github.com/your-fork/leo" ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang
AMARELEO_REPO="https://github.com/your-fork/amareleo-chain" ./build-publish-image.sh --dockerfile amareleo.Dockerfile --image-name amareleo-chain

# Other overrides
NODE_VERSION=18 DEBIAN_RELEASE=bullseye ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang
RUST_VERSION=1.88.0 ./build-publish-image.sh --dockerfile aleo-devnet.Dockerfile --image-name aleo-devnet
```