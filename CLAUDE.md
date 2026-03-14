# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

Docker containerization for the Aleo blockchain ecosystem: Leo Lang (aleo CLI) and integrated devnet environments with snarkOS. All images are multi-arch (AMD64/ARM64) and published to `ghcr.io/sealance-io/`.

## Essential Commands

### Building Docker Images

```bash
# Leo Lang standard image (with Node.js)
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang --no-push

# Aleo Devnet integrated image (Leo + snarkOS) — requires leo-lang image to exist first
./build-publish-image.sh --dockerfile aleo-devnet.Dockerfile --image-name aleo-devnet --no-push

# Local development builds (single architecture, faster)
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang --local-arch --no-push
```

### Building Deployment Snapshots

```bash
# Build deployment snapshot for custom branch/commit (without pushing to remote registry)
./build-publish-deployment-snapshot.sh --commit main --skip-push

# Build with custom versions and consensus target (and push)
./build-publish-deployment-snapshot.sh --commit main --version v3.5.0-v4.5.3 --consensus-version 13
```

### Running Containers

```bash
# Run Leo Lang CLI
docker run --rm ghcr.io/sealance-io/leo-lang:v3.5.0 leo --help

# Run Aleo devnet (Leo v3 + snarkOS)
docker run -it --rm -p 3030:3030 -p 4130:4130 -v $(pwd)/data:/data ghcr.io/sealance-io/aleo-devnet:v3.5.0-v4.5.3

# Run local testnet with docker-compose (4 validators + 1 client)
# NOTE: requires locally-tagged image "localhost/snarkos:devnet-v4.5.3"
docker-compose up -d

# Access REST API after testnet starts
curl http://localhost:3030/testnet/latest/height
```

### Publishing Images (requires GitHub registry login)

```bash
echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang --no-latest
```

## Architecture & Key Relationships

### Image Dependency Chain

**`leo-lang` must be built and published before `aleo-devnet`**. The `aleo-devnet.Dockerfile` uses `FROM ghcr.io/sealance-io/leo-lang:${LEO_VERSION}` to copy the Leo binary. This is an ARG workaround since `COPY --from` doesn't support build args directly.

### Dockerfile Structure

All Dockerfiles use multi-stage builds with cargo-chef for dependency caching:

1. **leo.Dockerfile**:
   - `planner`: Clones Leo repo, extracts `rust-toolchain.toml`, generates cargo-chef recipe
   - `builder`: Cooks dependencies (cached layer), then compiles Leo source
   - `leo`: Minimal runtime with Node.js, non-root `leo` user (UID 1001)

2. **aleo-devnet.Dockerfile**:
   - `leo-image`: References pre-built `leo-lang` image for binary extraction
   - `snarkos-planner`: Clones snarkOS, extracts `rust-toolchain.toml`, generates recipe
   - `snarkos-builder`: Cooks dependencies, builds snarkOS with `test_network` feature
   - Final stage: Combines Leo + snarkOS binaries, pre-downloads prover parameters

### Rust Toolchain Version Handling

Two layers of Rust version management work together:

1. **Build-time inference** (`build-publish-image.sh` and CI): If `RUST_VERSION` is not explicitly set, the `infer_rust_version()` function fetches the upstream project's `rust-toolchain.toml` from GitHub (via raw.githubusercontent.com) and extracts the `channel` value. This sets the Docker **base image** tag (`rust:${RUST_VERSION}-slim-trixie`). Falls back to `1.92.0` if inference fails or the channel is nightly.

2. **Dockerfile-level deferral**: Regardless of the base image version, the actual Rust compiler used for compilation is determined by the upstream `rust-toolchain.toml`. During the planner stage, this file is copied from the cloned repo and propagated to the builder stage via `COPY --from=planner`. The base image just needs `rustup` to install the required toolchain.

In practice, inference (step 1) tries to align the base image with what the Dockerfile will need (step 2), avoiding an unnecessary toolchain download during the build. Set `RUST_VERSION` explicitly only to override this behavior.

### Critical Implementation Details

**Prover Downloads**: `download-provers.sh` downloads mainnet parameter files (~2GB) to `/.aleo/resources/`. These are required for zero-knowledge proof generation and are pre-cached in images to avoid runtime downloads. Downloads run in parallel (4 at a time).

**snarkOS Build Features**: `default,snarkos-node-metrics,test_network` — the `test_network` feature is required for devnet operation.

**Docker Compose Network**: Uses `localhost/snarkos:devnet-v4.5.3` (locally-tagged image, not from GHCR). Fixed IP addressing (172.20.0.0/16):
- validator0: 172.20.0.2 (verbose logging, REST disabled)
- validator1-3: 172.20.0.3-5 (quiet logging)
- client0: 172.20.0.6 (REST API on port 3030)

The `CONSENSUS_VERSION_HEIGHTS` environment variable (commented out in docker-compose.yaml) can be set to a comma-separated list of heights to accelerate consensus version transitions in devnet.

### Build Script Intelligence

**`build-publish-image.sh`**:
- Auto-detects Docker vs Podman, sets up multi-arch builders dynamically
- Handles version-specific build arguments based on `--image-name` (leo-lang vs aleo-devnet)
- Retries failed pushes up to 3 times with 10-second delays
- Uses script directory as build context (important for COPY commands)
- Flags: `--no-latest`, `--no-push`, `--local-arch`, `--variant`

**`build-publish-deployment-snapshot.sh`**:
- Clones `sealance-io/compliant-transfer-aleo` at specified `--commit`
- Starts devnet container, waits for initialization (credits.aleo available, consensus >= target)
- `--consensus-version N` sets target consensus height (default: 13), passes heights 0..N-1 via `CONSENSUS_VERSION_HEIGHTS` to accelerate reaching it
- Deploys programs, captures blockchain state, builds multi-arch image

### Environment Variables for Customization

`RUST_VERSION` is auto-inferred from the upstream `rust-toolchain.toml` — only set it to override.

```bash
LEO_VERSION="v3.5.0" SNARKOS_VERSION="v4.5.3" ./build-publish-image.sh --dockerfile aleo-devnet.Dockerfile --image-name aleo-devnet
LEO_REPO="https://github.com/your-fork/leo" ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang
NODE_VERSION=18 DEBIAN_RELEASE=bullseye ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang
# Override auto-inferred Rust version (rarely needed):
RUST_VERSION=1.85.0 ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang
```

## CI/CD Automation

GitHub Actions workflows (in `.github/workflows/`):
- **`build-publish-image.yml`**: Reusable workflow for multi-arch builds (called via `workflow_call`)
- **`manual-build.yml`**: Entry point for manual builds via `workflow_dispatch`
- **`check-updates.yml`**: Version detection — scans upstream Leo (ProvableHQ/leo) and snarkOS (ProvableHQ/snarkOS) for new releases. Minimum versions: Leo >= v3.5.0, snarkOS >= v4.5.3. The scheduled cron is currently disabled; trigger manually via `gh workflow run check-updates.yml`
- **`build-publish-deployment-snapshot.yml`**: Creates pre-deployed devnet images. Uses `setup-leo-action` on the runner for Leo CLI (not Docker), and `docker cp` instead of volume mounts to avoid Docker-in-Docker path issues

### Triggering CI from the CLI

```bash
# Trigger a manual image build
gh workflow run manual-build.yml -f image_name=leo-lang -f leo_version=v3.5.0

# Trigger an aleo-devnet build
gh workflow run manual-build.yml -f image_name=aleo-devnet -f leo_version=v3.5.0 -f snarkos_version=v4.5.3

# Check for upstream version updates
gh workflow run check-updates.yml

# Trigger a deployment snapshot build
gh workflow run build-publish-deployment-snapshot.yml -f git-ref=main -f aleo-devnet-version=v3.5.0-v4.5.3
```

### Build Optimizations

| Optimization | Benefit |
|---|---|
| **Native ARM64 runners** (`ubuntu-24.04-arm`) | Avoids QEMU emulation (10-20x slower) |
| **Parallel matrix builds** | AMD64 and ARM64 build simultaneously |
| **Cargo-chef in Dockerfiles** | Caches compiled dependencies between builds |
| **Registry-based caching** | Stores layers in GHCR (no 10GB GHA cache limit) |
| **Push-by-digest + merge** | Parallel builds, then manifest merge |

Build time improvement: **4-6 hours → ~45-50 minutes**. See [docs/CI.md](docs/CI.md) for detailed CI/CD documentation including push-by-digest pattern and registry caching details.