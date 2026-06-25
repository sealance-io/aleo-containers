# AGENTS.md

Docker containerization for the Aleo blockchain ecosystem: Leo Lang (aleo CLI) and integrated devnet environments with snarkOS. All images are multi-arch (AMD64/ARM64) and published to `ghcr.io/sealance-io/`.

## Deep-Dive Reference

Read the relevant doc when working on the corresponding subsystem:

| When working on... | Read |
|---|---|
| Dockerfiles, multi-stage builds, Rust toolchain | [docs/architecture.md](docs/architecture.md) |
| Entrypoint, devnet env vars, snapshots, validation | [docs/devnet.md](docs/devnet.md) |
| Build scripts, flags, env customization | [docs/building.md](docs/building.md) |
| CI workflows, GitHub Actions, security | [docs/CI.md](docs/CI.md) |

## Image Dependency Chain

```
leo.Dockerfile → ghcr.io/sealance-io/leo-lang:vX.Y.Z
                        ↓ (COPY --from)
aleo-devnet.Dockerfile → ghcr.io/sealance-io/aleo-devnet:vX.Y.Z-vA.B.C
                                ↓ (FROM base, no CMD override)
snapshot Dockerfile (generated) → ghcr.io/sealance-io/aleo-devnet-custom:tag
```

## Essential Commands

### Build Images

```bash
# Leo Lang (with Node.js)
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang --no-push

# Aleo Devnet (Leo + snarkOS) — requires leo-lang to exist first
./build-publish-image.sh --dockerfile aleo-devnet.Dockerfile --image-name aleo-devnet --no-push

# Local dev build (single arch, fastest)
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang --local-arch --no-push
```

### Build Deployment Snapshots

```bash
./build-publish-deployment-snapshot.sh --commit main --skip-push
./build-publish-deployment-snapshot.sh --commit main --version v4.3.0-v4.8.1 --consensus-version 16
```

### Run Containers

```bash
docker run --rm ghcr.io/sealance-io/leo-lang:v4.3.0 leo --help
docker run -it --rm -p 3030:3030 -p 4130:4130 -v $(pwd)/data:/aleo/data ghcr.io/sealance-io/aleo-devnet:v4.3.0-v4.8.1
curl http://localhost:3030/testnet/latest/height
```

### Lint & Validate

```bash
shellcheck --severity=warning *.sh
hadolint leo.Dockerfile
hadolint aleo-devnet.Dockerfile
```

## Shell Script Conventions

All scripts use `set -euo pipefail` with `IFS=$'\n\t'` and are validated with [shellcheck](https://www.shellcheck.net/). Both build scripts support `--help` for full usage details.

## Key Gotchas

- **Build order**: `leo-lang` must be built/published before `aleo-devnet` (`COPY --from` dependency)
- **Version format**: Devnet tags are strictly `vX.Y.Z-vA.B.C` (Leo-snarkOS)
- **Leo source tag split**: Public image tags stay normalized (`LEO_VERSION=v4.3.0`), while Leo `v4.3.0` clones from upstream `LEO_SOURCE_TAG=leo-lang-v4.3.0`
- **snarkOS source tag split**: Same pattern — image component stays normalized (`SNARKOS_VERSION=v4.8.1`), while the clone/Rust inference use `SNARKOS_SOURCE_TAG=testnet-v4.8.1` (recorded via the `snarkos.source-tag` label). Other versions (e.g. `v4.7.3`) pass through unchanged
- **Minimum versions**: Leo >= v3.5.0, snarkOS >= v4.5.3 (required for non-root user and `/aleo/data` layout)
- **Hadolint ignores**: `.hadolint.yaml` ignores DL3008 and DL3059 intentionally — do not remove
- **Rust version**: `RUST_VERSION` is auto-inferred from upstream `rust-toolchain.toml`; keep it per component (Leo v4.3.0 uses 1.96.0, snarkOS v4.8.1 / `testnet-v4.8.1` declares 1.88 and Docker base tags normalize to 1.88.0)
- **Snapshot consensus**: Deployment snapshots default to consensus version 16 and generated heights `0..15`
- **Fail-closed policy**: Publish flows require a non-empty program list from `required-programs.txt`
- **SHA-pinned actions**: All workflow `uses:` reference full commit SHAs, not mutable tags — include version as trailing comment
- **`persist-credentials: false`**: Required on all `actions/checkout` steps
- **Minimal permissions**: `permissions: {}` at workflow level, explicit per-job grants
- **Env indirection**: Never interpolate `github.*`/`inputs.*` directly in `run:` scripts — pass through `env:` blocks
- **Job-level change detection**: CI uses job-level (not workflow-level `paths`) to avoid stuck required checks on unrelated PRs
