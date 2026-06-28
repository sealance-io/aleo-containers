# Dockerfile Architecture

## Multi-Stage Build Structure

All Dockerfiles use multi-stage builds with [cargo-chef](https://github.com/LukeMathWalker/cargo-chef) for dependency caching:

### leo.Dockerfile

| Stage | Purpose |
|---|---|
| `planner` | Clones Leo repo, extracts `rust-toolchain.toml`, generates cargo-chef recipe |
| `builder` | Cooks dependencies (cached layer), then compiles Leo source |
| `leo` | Minimal runtime with Node.js, non-root `leo` user (UID 1001) |

### aleo-devnet.Dockerfile

| Stage | Purpose |
|---|---|
| `leo-image` | References pre-built `leo-lang` image for binary extraction |
| `snarkos-planner` | Clones snarkOS, extracts `rust-toolchain.toml`, generates recipe |
| `snarkos-builder` | Cooks dependencies, builds snarkOS with `test_network` feature |
| Final stage | Combines Leo + snarkOS binaries, pre-downloads prover parameters |

## Non-Root User

Both images create a `leo` user (UID 1001, GID 1001). Key directories:

- **leo-lang**: `/.aleo/resources/` (prover parameters), `/app` (working directory)
- **aleo-devnet**: `/home/leo/.aleo/resources/` (prover parameters), `/aleo` (workdir), `/aleo/data` (blockchain storage volume)

Prover download and entrypoint script execution happen as `leo` user. The UID is consistent across images for cross-image compatibility.

## Rust Toolchain Version Handling

Two layers of Rust version management work together:

1. **Build-time inference** (`build-publish-image.sh` and CI): If `RUST_VERSION` is not explicitly set, `infer_rust_version()` fetches the upstream project's `rust-toolchain.toml` from GitHub and extracts the `channel` value. This sets the Docker **base image** tag (`rust:${RUST_VERSION}-slim-trixie`). Leo inference uses `LEO_SOURCE_TAG` (default `leo-lang-v4.3.1` for image tag `v4.3.1`), while snarkOS inference uses `SNARKOS_SOURCE_TAG` (default `testnet-v4.8.1` for image tag `v4.8.1`).

2. **Dockerfile-level deferral**: The actual Rust compiler used is determined by the upstream `rust-toolchain.toml` copied from the cloned repo during the planner stage. The base image just needs `rustup` to install the required toolchain.

In practice, inference (step 1) tries to align the base image with what the Dockerfile will need (step 2), avoiding an unnecessary toolchain download. Set `RUST_VERSION` explicitly only to override. Keep Rust per component: Leo `v4.3.1` requires Rust `1.96.0`; snarkOS `v4.8.1` (source tag `testnet-v4.8.1`) still declares Rust `1.88`, normalized to Docker base tag `1.88.0`.

## Leo Source Tags vs Image Tags

Published image tags are normalized (`ghcr.io/sealance-io/leo-lang:v4.3.1`), but upstream Leo source uses `leo-lang-v4.3.1`. `LEO_VERSION` controls the image tag and metadata; `LEO_SOURCE_TAG` controls the git clone and Rust toolchain inference. If unset, known Leo releases with `leo-lang-*` upstream tags derive the matching source tag automatically; older/manual versions fall back to `LEO_VERSION`.

## snarkOS Source Tags vs Image Tags

snarkOS uses the same split as Leo. The `aleo-devnet` image component stays a normalized `vX.Y.Z` tag (`SNARKOS_VERSION`, e.g. `v4.8.1`, used for image tags and the `snarkos.version` label), while `SNARKOS_SOURCE_TAG` controls the git clone and Rust toolchain inference. This matters when upstream ships a release under a non-`vX.Y.Z` tag: `v4.8.1` is published from the pre-release tag `testnet-v4.8.1`. If unset, `SNARKOS_SOURCE_TAG` derives `testnet-v4.8.1` only for `SNARKOS_VERSION=v4.8.1`; other versions (e.g. `v4.7.3`) fall back to using `SNARKOS_VERSION` unchanged. The resolved source tag is recorded on the image via the `snarkos.source-tag` label.

For the current default devnet image, Leo `leo-lang-v4.3.1` and snarkOS `testnet-v4.8.1` both resolve snarkVM to commit `357899f8e85d6340bda5db8373b1cdffdf88a6d7`.

## Prover Downloads

`download-provers.sh` downloads 9 mainnet parameter files (~2GB total) to the directory specified by `DEST_DIR`. Downloads run in parallel batches of 4, with per-file success/failure tracking. Any single failure causes a non-zero exit.

## snarkOS Build Features

Feature set: `default,snarkos-node-metrics,test_network` — the `test_network` feature is required for devnet operation.
