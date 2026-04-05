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

1. **Build-time inference** (`build-publish-image.sh` and CI): If `RUST_VERSION` is not explicitly set, `infer_rust_version()` fetches the upstream project's `rust-toolchain.toml` from GitHub and extracts the `channel` value. This sets the Docker **base image** tag (`rust:${RUST_VERSION}-slim-trixie`). Falls back to `1.92.0` if inference fails or the channel is nightly.

2. **Dockerfile-level deferral**: The actual Rust compiler used is determined by the upstream `rust-toolchain.toml` copied from the cloned repo during the planner stage. The base image just needs `rustup` to install the required toolchain.

In practice, inference (step 1) tries to align the base image with what the Dockerfile will need (step 2), avoiding an unnecessary toolchain download. Set `RUST_VERSION` explicitly only to override.

## Prover Downloads

`download-provers.sh` downloads 9 mainnet parameter files (~2GB total) to the directory specified by `DEST_DIR`. Downloads run in parallel batches of 4, with per-file success/failure tracking. Any single failure causes a non-zero exit.

## snarkOS Build Features

Feature set: `default,snarkos-node-metrics,test_network` — the `test_network` feature is required for devnet operation.
