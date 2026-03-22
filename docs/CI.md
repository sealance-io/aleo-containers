# 🔄 CI/CD Workflows

This repository uses GitHub Actions to automate the building and publishing of Docker images.

## Automated Version Detection

A workflow checks for new releases of Leo and snarkOS:

- Scheduled cron is currently disabled; trigger manually via `gh workflow run check-updates.yml`
- Scans both Leo and snarkOS repositories for new release tags
- Only processes versions that meet minimum requirements (Leo >= v3.5.0, snarkOS >= v4.5.4)
- Compares against existing images in the registry to avoid rebuilding
- Triggers `leo-lang` builds for new Leo versions
- Triggers `aleo-devnet` builds for new Leo+snarkOS combinations

## Build Workflows

The build system consists of these primary workflows:

1. **Reusable Build Workflow** (`build-publish-image.yml`)
   - Core functionality for building and pushing images
   - Handles multi-architecture builds (AMD64/ARM64)
   - Called by other workflows via `workflow_call`

2. **Manual Build Workflow** (`manual-build.yml`)
   - Entry point for manual builds via GitHub UI or `gh` CLI
   - Derives parameters (dockerfile, version tags) from minimal inputs
   - Calls the reusable build workflow

3. **Update Detection** (`check-updates.yml`)
   - Monitors upstream Leo and snarkOS repositories for new versions
   - Applies semantic versioning filters
   - Triggers `leo-lang` builds for new Leo versions
   - Triggers `aleo-devnet` builds for new Leo+snarkOS combinations

4. **Deployment Snapshot Workflow** (`build-publish-deployment-snapshot.yml`)
   - Creates custom Aleo devnet images with pre-deployed programs
   - Clones and deploys programs from compliant-transfer-aleo repository
   - Volume mount narrowed to `/aleo/data` — only ledger state is captured
   - 3-layer validation: pre-shutdown program verification, post-build per-platform E2E, fail-closed publish gate
   - Latest tag is a retag of the verified version-tag digest (via `docker buildx imagetools create`), not a rebuild
   - Reads `required-programs.txt` by default; override with `required-programs` input

## Build Optimizations

The CI pipeline includes several optimizations to reduce build times from 4-6 hours to ~45-50 minutes:

### Native ARM64 Runners (No QEMU Emulation)

Multi-arch builds use **native runners per architecture** instead of QEMU emulation:

```
┌─────────────────────────────────────────────────────────────┐
│                    build-standard job                        │
├─────────────────────────────────────────────────────────────┤
│  Matrix:                                                     │
│    ├── linux/amd64 → ubuntu-24.04      (native x86_64)      │
│    └── linux/arm64 → ubuntu-24.04-arm  (native ARM64)       │
│                                                              │
│  Both run in PARALLEL, then merge into multi-arch manifest  │
└─────────────────────────────────────────────────────────────┘
```

QEMU emulation is 10-20x slower for Rust compilation. Native runners eliminate this bottleneck.

### Cargo-Chef Dependency Caching

Dockerfiles use [cargo-chef](https://github.com/LukeMathWalker/cargo-chef) to separate dependency compilation from source compilation:

```
┌─────────────────────────────────────────────────────────────┐
│  planner stage:  Generate recipe.json from Cargo.toml/lock │
│       ↓                                                      │
│  builder stage:  cargo chef cook (compile deps) ← CACHED    │
│       ↓                                                      │
│  builder stage:  cargo build (compile source)  ← Fast       │
└─────────────────────────────────────────────────────────────┘
```

When only source code changes (not dependencies), the expensive dependency compilation layer is reused from cache.

### Registry-Based Layer Caching

Build layers are cached in GitHub Container Registry instead of GitHub Actions cache:

```yaml
cache-from: type=registry,ref=ghcr.io/sealance-io/leo-lang:cache-linux-amd64
cache-to:   type=registry,ref=ghcr.io/sealance-io/leo-lang:cache-linux-amd64,mode=max
```

Benefits over GitHub Actions cache:
- No 10GB size limit
- Architecture-specific caches (no cross-arch pollution)
- Longer retention
- `mode=max` caches all intermediate layers

### Push-by-Digest Pattern

Each architecture builds and pushes by content digest, then a merge job creates the multi-arch manifest:

```
build-standard (amd64) ──→ push @sha256:abc...  ─┐
                                                  ├─→ merge-standard ──→ tag: v3.5.0
build-standard (arm64) ──→ push @sha256:def...  ─┘
```

This enables parallel builds without manifest conflicts.

## Manual Builds

You can manually trigger builds through the GitHub Actions interface:

### Standard Images

1. Navigate to the "Actions" tab in the repository
2. Select the "Build Docker Images" workflow
3. Click "Run workflow"
4. Fill in the required parameters:
   - Image name (`leo-lang` or `aleo-devnet`)
   - Version tag
   - Other optional settings

### Deployment Snapshots

1. Navigate to the "Actions" tab in the repository
2. Select the "Create aleo-devnet deployment snapshot" workflow
3. Click "Run workflow"
4. Fill in the required parameters:
   - Git reference (branch/tag/commit) to deploy
   - Aleo devnet base image version
   - Custom image name
   - Whether to push as latest
   - Required programs to verify (optional; defaults to `required-programs.txt`)

This is useful for:
- Testing specific versions that might not be automatically detected
- Creating custom devnet images with your deployed programs
- Building deployment snapshots from specific branches or commits

## How It Works

### Automated Version Detection

1. The weekly check uses GitHub API to fetch release tags from upstream
2. It normalizes version strings for proper semantic comparison
3. Tags below the minimum version threshold are filtered out
4. Existing registry tags are checked to avoid duplicate builds
5. For each new qualifying tag, a build workflow is triggered
6. Images are built and published to the GitHub Container Registry

### Deployment Snapshot Creation

1. The workflow clones the compliant-transfer-aleo repository at the specified ref
2. Resolves required programs from `required-programs.txt` (or the `required-programs` input override). Publish flows fail if the list is empty.
3. Starts an Aleo devnet container with volume mounted at `/aleo/data` (only ledger state)
4. Waits for the devnet consensus version to reach the target (default: >= 13)
5. Installs dependencies and builds the programs
6. Deploys the programs to the local devnet
7. **Pre-shutdown verification**: Queries the REST API for each required program (retries up to 10x)
8. Stops the container and extracts only `/aleo/data` to `./devnet/data/` via `docker cp`
9. Builds the multi-architecture image (version-tag only)
10. **Post-build E2E verification**: Boots the built image per-platform (amd64 + arm64 via QEMU), waits for REST API, re-verifies all required programs
11. **Retags as latest**: Uses `docker buildx imagetools create` to retag the verified version-tag digest — no second build

The entire process ensures:
- New versions are automatically built while maintaining strict version requirements
- Deployment snapshots capture only blockchain state, not runtime files from the base image
- Required programs are verified both before shutdown and after image build (per-platform)
- The `latest` tag always points to a verified digest — never published without E2E validation
- All images support both x86_64 and ARM64 architectures