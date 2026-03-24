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
./build-publish-deployment-snapshot.sh --commit main --version v3.5.0-v4.5.4 --consensus-version 13

# Override required programs for verification (default: from required-programs.txt)
./build-publish-deployment-snapshot.sh --commit main --skip-push --required-programs "merkle_tree.aleo,custom.aleo"
```

### Running Containers

```bash
# Run Leo Lang CLI
docker run --rm ghcr.io/sealance-io/leo-lang:v3.5.0 leo --help

# Run Aleo devnet (Leo v3 + snarkOS)
docker run -it --rm -p 3030:3030 -p 4130:4130 -v $(pwd)/data:/aleo/data ghcr.io/sealance-io/aleo-devnet:v3.5.0-v4.5.4

# Run local testnet with docker-compose (4 validators + 1 client)
# NOTE: requires locally-tagged image "localhost/snarkos:devnet-v4.5.4"
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

```
leo.Dockerfile → ghcr.io/sealance-io/leo-lang:vX.Y.Z
                        ↓ (COPY --from)
aleo-devnet.Dockerfile → ghcr.io/sealance-io/aleo-devnet:vX.Y.Z-vA.B.C
                                ↓ (FROM base, no CMD override)
snapshot Dockerfile (generated) → ghcr.io/sealance-io/aleo-devnet-custom:tag
```

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

### Non-Root User

Both images create a `leo` user (UID 1001, GID 1001). Key directories:
- **leo-lang**: `/.aleo/resources/` (prover parameters), `/app` (working directory)
- **aleo-devnet**: `/home/leo/.aleo/resources/` (prover parameters), `/aleo` (workdir), `/aleo/data` (blockchain storage volume)

Prover download and entrypoint script execution happen as `leo` user. The UID is consistent across images for cross-image compatibility.

### Devnet Entrypoint (`devnet-entrypoint.sh`)

The `aleo-devnet` image uses a wrapper entrypoint with **three-way branching**:

| Docker invocation | Args received | Entrypoint behavior |
|---|---|---|
| `docker run <image>` | none (`CMD []`) | Env-driven: builds `leo devnet` command from env vars |
| `docker run <image> devnet --custom` | `devnet --custom` | Explicit args: runs `leo devnet --custom` with log forwarding |
| `docker run <image> new my_project` | `new my_project` | Passthrough: `exec leo new my_project` (no wrapper) |

**Environment variables** (only used in the env-driven path, i.e., no args):

| Variable | Default | Description |
|---|---|---|
| `STORAGE` | `/aleo/data` | Blockchain data directory |
| `VERBOSITY` | `4` | Log verbosity 0-4 |
| `NUM_VALIDATORS` | `4` | Number of validators |
| `NUM_CLIENTS` | `1` | Number of clients |
| `CLEAR_STORAGE` | `no` | `yes` to clear storage on start |
| `SNARKOS_FEATURES` | `test_network` | snarkOS features flag |
| `LOG_WAIT_SECONDS` | `5` | Wait before tailing logs |
| `LOG_POLL_INTERVAL` | `3` | Seconds between log file discovery |
| `LOG_FORWARDING` | `false` | Forward snarkOS logs to container stdout: `true`/`false` |

The wrapper also provides:
- **Log forwarding**: When `LOG_FORWARDING=true` (default), dynamically discovers snarkOS log files in `/tmp` and `${STORAGE}`, tails them to container stdout with `tail -F` (handles rotation). Set `LOG_FORWARDING=false` to suppress log tailing and informational wrapper messages (errors/shutdown messages still emitted)
- **Graceful shutdown**: Traps SIGTERM/SIGINT/SIGQUIT, sends SIGTERM to leo, waits up to 30s, then SIGKILL

### Snapshot Images

Generated snapshot Dockerfiles (`build-publish-deployment-snapshot.sh` and CI workflow) are minimal:
- `FROM ghcr.io/sealance-io/aleo-devnet:${DEVNET_VERSION}`
- `COPY --chown=leo:leo ./devnet/data /aleo/data` (pre-deployed blockchain state only)
- **No CMD or ENTRYPOINT override** — inherits base image's `CMD []` + entrypoint wrapper

This means snapshot images are fully configurable via `-e` env vars, just like the base image. Passing explicit args on `docker run` overrides this as expected.

### Snapshot Build Flow

1. Clone `sealance-io/compliant-transfer-aleo` at specified commit (SSH with fallback)
2. `npm ci --ignore-scripts` + `npm run postinstall` + `npm run build` + `npm run compile`
3. Start devnet container with volume mounted at `/aleo/data` (only captures ledger state, not runtime files)
4. Generate `CONSENSUS_VERSION_HEIGHTS=0,1,2,...,N-1` to accelerate reaching target consensus version
5. Poll `http://localhost:3030/testnet/consensus_version` until >= target (max 100 retries, 5s apart)
6. Deploy programs via `npm run deploy:devnet`
7. **Pre-shutdown verification**: Query REST API for each program in `required-programs.txt` (retries up to 10x)
8. Stop container, extract only `/aleo/data` to `./devnet/data/` (script uses alpine cp from volume; CI uses `docker cp`)
9. Build multi-arch image (version-tag only) from generated Dockerfile
10. **Post-build E2E verification**: Boot the built image per-platform (amd64 + arm64), wait for REST API, re-verify all required programs
11. **Retag as latest**: `docker buildx imagetools create` (same digest, no rebuild) — only after E2E passes

### Snapshot Build Validation

Three-layer verification prevents publishing snapshots with missing programs:

| Layer | When | What |
|---|---|---|
| **Volume narrowing** | Container run | Mount only `/aleo/data`, not `/aleo` — excludes `devnet-entrypoint.sh` and `snarkos` from capture |
| **Pre-shutdown check** | After `deploy:devnet`, before stop | REST API query per program with retries |
| **Post-build E2E** | After image build, before latest tag | Boot image per-platform, verify programs are queryable |

**`required-programs.txt`** (repo root): One program ID per line (`#` comments and blank lines ignored). Both the script and CI workflow read this file as the default. Override with `--required-programs` (script) or `required-programs` input (CI).

**Fail-closed policy**: Publish flows (`--skip-push=false`) **require** a non-empty program list. If `required-programs.txt` is missing/empty and no override is provided, the build aborts. Local-only builds (`--skip-push`) warn but continue without verification.

### Rust Toolchain Version Handling

Two layers of Rust version management work together:

1. **Build-time inference** (`build-publish-image.sh` and CI): If `RUST_VERSION` is not explicitly set, `infer_rust_version()` fetches the upstream project's `rust-toolchain.toml` from GitHub and extracts the `channel` value. This sets the Docker **base image** tag (`rust:${RUST_VERSION}-slim-trixie`). Falls back to `1.92.0` if inference fails or the channel is nightly.

2. **Dockerfile-level deferral**: The actual Rust compiler used is determined by the upstream `rust-toolchain.toml` copied from the cloned repo during the planner stage. The base image just needs `rustup` to install the required toolchain.

In practice, inference (step 1) tries to align the base image with what the Dockerfile will need (step 2), avoiding an unnecessary toolchain download. Set `RUST_VERSION` explicitly only to override.

### Critical Implementation Details

**Prover Downloads**: `download-provers.sh` downloads 9 mainnet parameter files (~2GB total) to the directory specified by `DEST_DIR`. Downloads run in parallel batches of 4, with per-file success/failure tracking. Any single failure causes a non-zero exit.

**snarkOS Build Features**: `default,snarkos-node-metrics,test_network` — the `test_network` feature is required for devnet operation.

**Docker Compose Network**: Uses `localhost/snarkos:devnet-v4.5.4` (locally-tagged image, not from GHCR). Fixed IP addressing (172.20.0.0/16):
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
- Version format is strictly `vX.Y.Z-vA.B.C` (Leo-snarkOS)
- Minimum versions: Leo >= v3.5.0, snarkOS >= v4.5.3 (required for non-root `leo` user and `/aleo/data` layout)
- Volume mount narrowed to `/aleo/data` — only ledger state is captured
- Flags: `--commit`, `--version`, `--consensus-version`, `--required-programs`, `--skip-push`
- Latest tag is a retag of the verified version-tag digest, not a second build

### Environment Variables for Customization

`RUST_VERSION` is auto-inferred from the upstream `rust-toolchain.toml` — only set it to override.

```bash
LEO_VERSION="v3.5.0" SNARKOS_VERSION="v4.5.4" ./build-publish-image.sh --dockerfile aleo-devnet.Dockerfile --image-name aleo-devnet
LEO_REPO="https://github.com/your-fork/leo" ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang
NODE_VERSION=18 DEBIAN_RELEASE=bullseye ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang
# Override auto-inferred Rust version (rarely needed):
RUST_VERSION=1.85.0 ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang
```

## CI/CD Automation

GitHub Actions workflows (in `.github/workflows/`):
- **`build-publish-image.yml`**: Reusable workflow for multi-arch builds (called via `workflow_call`)
- **`manual-build.yml`**: Entry point for manual builds via `workflow_dispatch`
- **`check-updates.yml`**: Version detection — scans upstream Leo (ProvableHQ/leo) and snarkOS (ProvableHQ/snarkOS) for new releases. Minimum versions: Leo >= v3.5.0, snarkOS >= v4.5.4. The scheduled cron is currently disabled; trigger manually via `gh workflow run check-updates.yml`
- **`build-publish-deployment-snapshot.yml`**: Creates pre-deployed devnet images. Uses `setup-leo-action` on the runner for Leo CLI (not Docker), and `docker cp` instead of volume mounts to avoid Docker-in-Docker path issues. Tags snapshots as `${DEVNET_VERSION}-${SHORT_SHA}`. Includes 3-layer validation: narrowed volume mount, pre-shutdown program verification, post-build per-platform E2E. Latest tag is a retag of the verified digest via `docker buildx imagetools create`

### Triggering CI from the CLI

```bash
# Trigger a manual image build
gh workflow run manual-build.yml -f image_name=leo-lang -f leo_version=v3.5.0

# Trigger an aleo-devnet build
gh workflow run manual-build.yml -f image_name=aleo-devnet -f leo_version=v3.5.0 -f snarkos_version=v4.5.4

# Check for upstream version updates
gh workflow run check-updates.yml

# Trigger a deployment snapshot build
gh workflow run build-publish-deployment-snapshot.yml -f git-ref=main -f aleo-devnet-version=v3.5.0-v4.5.4

# Trigger with custom program verification override
gh workflow run build-publish-deployment-snapshot.yml -f git-ref=main -f aleo-devnet-version=v3.5.0-v4.5.4 -f required-programs="merkle_tree.aleo"
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
