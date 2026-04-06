# 🔄 CI/CD Workflows

This repository uses GitHub Actions to automate building, publishing, linting, and security scanning of Docker images.

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
   - See [Deployment Snapshot Creation](#deployment-snapshot-creation) for the full step-by-step flow

## Linting & Security

Two additional workflows run on push/PR to `main` and enforce required branch protection checks:

5. **Lint** (`lint.yml`)
   - **ShellCheck** (`--severity=warning`) for all `*.sh` scripts
   - **Hadolint** (`--failure-threshold error`) for all `*.Dockerfile` files
   - Rollup job `lint-status` is a **required status check** for PRs

6. **Security Audit** (`security-audit.yml`)
   - **Zizmor** audits workflow files (pedantic on PR/push, auditor persona on weekly schedule)
   - **Trivy config scan** for Dockerfile misconfigurations — fails on HIGH/CRITICAL
   - **Trivy + Grype image scans** of published images — report-only, schedule/manual only
   - Rollup job `security-status` is a **required status check** for PRs

Both workflows use **job-level change detection** (not workflow-level `paths` filters) to avoid stuck "Pending" required checks on unrelated PRs.

### CI Hardening Patterns

All workflows follow these security patterns — maintain them when editing `.github/workflows/`:

- **SHA-pinned actions**: Every `uses:` references a full commit SHA, not a mutable tag. Include the version as a trailing comment (e.g., `# v6.0.2`)
- **`persist-credentials: false`** on all `actions/checkout` steps
- **Minimal permissions**: `permissions: {}` at workflow level, explicit per-job grants
- **Env indirection**: Workflow context values (`github.*`, `inputs.*`) pass through `env:` blocks, never interpolated directly in `run:` scripts

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
                                                  ├─→ merge-standard ──→ tag: v4.0.0
build-standard (arm64) ──→ push @sha256:def...  ─┘
```

This enables parallel builds without manifest conflicts.

## Manual Builds

Trigger builds via GitHub Actions UI or the `gh` CLI:

```bash
# Build a leo-lang image
gh workflow run manual-build.yml -f image_name=leo-lang -f leo_version=v4.0.0

# Build an aleo-devnet image
gh workflow run manual-build.yml -f image_name=aleo-devnet -f leo_version=v4.0.0 -f snarkos_version=v4.6.0

# Build a deployment snapshot
gh workflow run build-publish-deployment-snapshot.yml \
  -f git-ref=main -f aleo-devnet-version=v4.0.0-v4.6.0

# Check for upstream version updates
gh workflow run check-updates.yml
```

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