# Build Scripts

## build-publish-image.sh

- Auto-detects Docker vs Podman, sets up multi-arch builders dynamically
- Handles version-specific build arguments based on `--image-name` (leo-lang vs aleo-devnet)
- Retries failed pushes up to 3 times with 10-second delays
- Uses script directory as build context (important for COPY commands)
- Flags: `--no-latest`, `--no-push`, `--local-arch`, `--variant`

```bash
./build-publish-image.sh --help
```

## build-publish-deployment-snapshot.sh

- Version format is strictly `vX.Y.Z-vA.B.C` (Leo-snarkOS)
- Minimum versions: Leo >= v3.5.0, snarkOS >= v4.5.3 (required for non-root `leo` user and `/aleo/data` layout)
- Volume mount narrowed to `/aleo/data` — only ledger state is captured
- Flags: `--commit`, `--version`, `--consensus-version`, `--required-programs`, `--skip-push`
- Latest tag is a retag of the verified version-tag digest, not a second build

```bash
./build-publish-deployment-snapshot.sh --help
```

## Environment Variables

`RUST_VERSION` is auto-inferred from the upstream `rust-toolchain.toml` — only set it to override. Leo and snarkOS keep separate Rust policies: Leo `v4.3.1` uses Rust `1.96.0`, while snarkOS `v4.8.1` (source tag `testnet-v4.8.1`) declares Rust `1.88` and Docker base tags normalize to `1.88.0`.

Leo image tags and source tags are intentionally separate. `LEO_VERSION=v4.3.1` is the public image tag, while `LEO_SOURCE_TAG=leo-lang-v4.3.1` is the upstream git tag used for clone and Rust inference. If `LEO_SOURCE_TAG` is empty, known Leo releases with `leo-lang-*` upstream tags derive the matching source tag automatically; other versions fall back to `LEO_VERSION`.

snarkOS uses the same split: `SNARKOS_VERSION=v4.8.1` is the normalized image component, while `SNARKOS_SOURCE_TAG=testnet-v4.8.1` is the upstream git tag used for clone and Rust inference (needed because `v4.8.1` ships from the pre-release tag `testnet-v4.8.1`). If `SNARKOS_SOURCE_TAG` is empty, only the default `SNARKOS_VERSION=v4.8.1` derives `testnet-v4.8.1`; other versions (e.g. `v4.7.3`) fall back to `SNARKOS_VERSION`.

The default `v4.3.1-v4.8.1` devnet pair is aligned on snarkVM commit `357899f8e85d6340bda5db8373b1cdffdf88a6d7` (Leo via `testnet-v4.8.0`, snarkOS via its pinned rev).

| Variable | Applies to | Default | Description |
|---|---|---|---|
| `LEO_VERSION` | both | `v4.3.1` | Normalized Leo image/version tag |
| `LEO_SOURCE_TAG` | leo-lang | `leo-lang-v4.3.1` | Upstream Leo source tag |
| `SNARKOS_VERSION` | aleo-devnet | `v4.8.1` | Normalized snarkOS image/version tag |
| `SNARKOS_SOURCE_TAG` | aleo-devnet | `testnet-v4.8.1` | Upstream snarkOS source tag |
| `LEO_REPO` | both | ProvableHQ/leo | Leo Git URL |
| `RUST_VERSION` | both | auto-inferred | Rust base image tag |
| `NODE_VERSION` | leo-lang | `24` | Node.js major version |
| `DEBIAN_RELEASE` | both | `trixie` | Base image distribution |
| `REGISTRY` | both | `ghcr.io/sealance-io` | Container registry |

```bash
# Example: multiple overrides
LEO_VERSION="v4.3.1" SNARKOS_VERSION="v4.8.1" \
  ./build-publish-image.sh --dockerfile aleo-devnet.Dockerfile --image-name aleo-devnet

# Build from a fork
LEO_REPO="https://github.com/your-fork/leo" LEO_SOURCE_TAG="leo-lang-v4.3.1" \
  ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang

# Override Rust version (rarely needed)
RUST_VERSION=1.96.0 \
  ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang
```
