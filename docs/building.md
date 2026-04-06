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

`RUST_VERSION` is auto-inferred from the upstream `rust-toolchain.toml` — only set it to override.

| Variable | Applies to | Default | Description |
|---|---|---|---|
| `LEO_VERSION` | both | `v4.0.0` | Leo release tag |
| `SNARKOS_VERSION` | aleo-devnet | `v4.6.0` | snarkOS release tag |
| `LEO_REPO` | both | ProvableHQ/leo | Leo Git URL |
| `RUST_VERSION` | both | auto-inferred | Rust base image tag |
| `NODE_VERSION` | leo-lang | `24` | Node.js major version |
| `DEBIAN_RELEASE` | both | `trixie` | Base image distribution |
| `REGISTRY` | both | `ghcr.io/sealance-io` | Container registry |

```bash
# Example: multiple overrides
LEO_VERSION="v4.0.0" SNARKOS_VERSION="v4.6.0" \
  ./build-publish-image.sh --dockerfile aleo-devnet.Dockerfile --image-name aleo-devnet

# Build from a fork
LEO_REPO="https://github.com/your-fork/leo" \
  ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang

# Override Rust version (rarely needed)
RUST_VERSION=1.85.0 \
  ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang
```
