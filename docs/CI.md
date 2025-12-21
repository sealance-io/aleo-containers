# 🔄 CI/CD Workflows

This repository uses GitHub Actions to automate the building and publishing of Docker images.

## Automated Version Detection

A weekly workflow checks for new releases of Leo and snarkOS:

- Runs every Monday at 2:30 AM UTC
- Scans both Leo and snarkOS repositories for new release tags
- Only processes versions that meet minimum requirements (Leo >= v3.4.0, snarkOS >= v4.4.0)
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
   - Captures blockchain state after deployment
   - Builds multi-architecture images with the deployed state

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
cache-to:   type=registry,ref=ghcr.io/sealance-io/leo-lang:cache-linux-amd64,mode=min
```

Benefits over GitHub Actions cache:
- No 10GB size limit
- Architecture-specific caches (no cross-arch pollution)
- Longer retention
- `mode=min` caches final image layers (faster export than `mode=max`)

### Push-by-Digest Pattern

Each architecture builds and pushes by content digest, then a merge job creates the multi-arch manifest:

```
build-standard (amd64) ──→ push @sha256:abc...  ─┐
                                                  ├─→ merge-standard ──→ tag: v3.4.0
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
2. Starts an Aleo devnet container with the specified base image version
3. Waits for the devnet to be fully initialized:
   - Port 3030 to be accessible
   - credits.aleo program to be available
   - Consensus version to reach >= 10
4. Installs dependencies and builds the programs
5. Deploys the programs to the local devnet
6. Stops the container and extracts the blockchain state
7. Creates a new Docker image with the pre-deployed state
8. Builds and pushes multi-architecture images (AMD64/ARM64)

The entire process ensures:
- New versions are automatically built while maintaining strict version requirements
- Deployment snapshots capture a complete, ready-to-use blockchain state
- All images support both x86_64 and ARM64 architectures