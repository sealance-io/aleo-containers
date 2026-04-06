# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Multi-arch (AMD64/ARM64) Docker images for the Aleo blockchain ecosystem, published to `ghcr.io/sealance-io/`. Two image variants: **leo-lang** (Leo CLI + Node.js) and **aleo-devnet** (Leo + snarkOS for local test networks).

## Image Dependency Chain

```
leo.Dockerfile → ghcr.io/sealance-io/leo-lang:vX.Y.Z
                        ↓ (COPY --from)
aleo-devnet.Dockerfile → ghcr.io/sealance-io/aleo-devnet:vX.Y.Z-vA.B.C
                                ↓ (FROM base, no CMD override)
snapshot Dockerfile (generated) → ghcr.io/sealance-io/aleo-devnet-custom:tag
```

**Build order matters**: `leo-lang` must be built/published before `aleo-devnet`.

## Essential Commands

```bash
# Build leo-lang locally (single arch, fastest)
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang --local-arch --no-push

# Build aleo-devnet locally (requires leo-lang image)
./build-publish-image.sh --dockerfile aleo-devnet.Dockerfile --image-name aleo-devnet --local-arch --no-push

# Build deployment snapshot
./build-publish-deployment-snapshot.sh --commit main --skip-push

# Lint (required before completing any task)
shellcheck --severity=warning *.sh
hadolint leo.Dockerfile
hadolint aleo-devnet.Dockerfile
```

## Validation Rules

- When modifying shell scripts, validate with `shellcheck --severity=warning` before considering the task complete.
- When modifying Dockerfiles, validate with `hadolint` before considering the task complete.
- When modifying GitHub Actions workflows, verify SHA-pinned action references include a trailing version comment (e.g., `# v6.0.2`).

## Architecture

### Leo v3/v4 Dual Layout Support

`leo.Dockerfile` auto-detects Leo's workspace layout at build time:
- **Leo v4+**: Workspace with `crates/leo/Cargo.toml` — builds with `cargo build --release --locked -p leo-lang`
- **Leo v3**: Single-crate root — builds with `cargo build --release --locked`

Both produce the same `target/release/leo` binary. The detection is in the builder stage's `RUN` command.

### Multi-Stage Builds with cargo-chef

Both Dockerfiles use [cargo-chef](https://github.com/LukeMathWalker/cargo-chef) for dependency caching:
1. **Planner**: clones repo, extracts `rust-toolchain.toml`, generates `recipe.json`
2. **Builder**: cooks dependencies (cached layer), then compiles source
3. **Runtime**: minimal image with binaries and non-root `leo` user (UID 1001)

### Rust Toolchain Version Handling

Two layers work together:
1. **Build-time inference**: `infer_rust_version()` in the build script (and CI) fetches upstream `rust-toolchain.toml` to set the Docker base image tag. Falls back to `1.94.1`.
2. **Dockerfile-level**: The actual compiler is determined by `rust-toolchain.toml` copied from the cloned repo. The base image just needs `rustup`.

`RUST_VERSION` is auto-inferred — only override explicitly.

### Devnet Entrypoint Three-Way Branching

`devnet-entrypoint.sh` has three modes based on args:
- **No args** (`docker run <image>`): builds `leo devnet` from env vars (`STORAGE`, `VERBOSITY`, `NUM_VALIDATORS`, etc.)
- **`devnet` args** (`docker run <image> devnet --custom`): passes through with log forwarding
- **Non-devnet** (`docker run <image> new my_project`): `exec leo` passthrough (no wrapper)

## Key Gotchas

- **Version format**: Devnet tags are strictly `vX.Y.Z-vA.B.C` (Leo-snarkOS)
- **Minimum versions**: Leo >= v3.5.0, snarkOS >= v4.5.3 (validation guards in scripts and CI protect against pre-rootless base images)
- **Hadolint ignores**: `.hadolint.yaml` ignores DL3008 and DL3059 intentionally — do not remove
- **Fail-closed policy**: Publish flows require a non-empty program list from `required-programs.txt`
- **snarkOS features**: Build uses `default,snarkos-node-metrics,test_network` — `test_network` is required for devnet

### CI Hardening (maintain when editing workflows)

- **SHA-pinned actions**: All `uses:` reference full commit SHAs, not mutable tags — include version as trailing comment
- **`persist-credentials: false`**: Required on all `actions/checkout` steps
- **Minimal permissions**: `permissions: {}` at workflow level, explicit per-job grants
- **Env indirection**: Never interpolate `github.*`/`inputs.*` directly in `run:` scripts — pass through `env:` blocks
- **Job-level change detection**: CI uses job-level (not workflow-level `paths`) to avoid stuck required checks on unrelated PRs

## Deep-Dive Reference

Load these on demand when working on the corresponding subsystem:

| When working on... | Read |
|---|---|
| Dockerfiles, multi-stage builds, Rust toolchain | [docs/architecture.md](docs/architecture.md) |
| Entrypoint, devnet env vars, snapshots, validation | [docs/devnet.md](docs/devnet.md) |
| Build scripts, flags, env customization | [docs/building.md](docs/building.md) |
| CI workflows, GitHub Actions, security | [docs/CI.md](docs/CI.md) |
