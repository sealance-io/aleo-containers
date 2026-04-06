# Aleo Blockchain Docker Images

This repository provides multi-architecture (AMD64/ARM64) Docker images for Aleo blockchain tooling:

- **Leo Lang** (`leo-lang`): The Leo programming language CLI with Node.js, for building and running zero-knowledge applications
- **Aleo Devnet** (`aleo-devnet`): Integrated Leo + snarkOS environment for running local test networks

## 📦 Docker Images

### Pre-built Images

Pre-built images are available on GitHub Container Registry:

- **Leo Lang**: `ghcr.io/sealance-io/leo-lang:v4.0.0`
- **Aleo Devnet**: `ghcr.io/sealance-io/aleo-devnet:v4.0.0-v4.6.0`

### Custom Deployment Snapshots
- **With deployed programs**: `ghcr.io/sealance-io/aleo-devnet-custom:latest`

You can also use the `latest` tag to always get the most recent version.

### Image Contents

#### Leo Lang (`leo-lang`)
- Leo CLI v4.0.0
- Node.js v24
- Debian trixie (slim)
- Essential SSL libraries

#### Aleo Devnet Image (`aleo-devnet`)
- Leo CLI v4.0.0
- snarkOS v4.6.0
- Pre-downloaded mainnet prover parameters (~2GB)
- Debian trixie (slim)
- Essential runtime libraries
- Configured for local development

## 🚀 Usage

### Leo Lang

For development, deployment, and running Leo applications:

```bash
# Run the Leo CLI directly
docker run --rm ghcr.io/sealance-io/leo-lang:v4.0.0 leo --help

# Check installed versions
docker run --rm ghcr.io/sealance-io/leo-lang:v4.0.0

# Mount your project directory and work with Leo
docker run --rm -v $(pwd):/app -w /app ghcr.io/sealance-io/leo-lang:v4.0.0 leo build

# Start a shell in the container
docker run --rm -it -v $(pwd):/app -w /app ghcr.io/sealance-io/leo-lang:v4.0.0 /bin/bash
```

### Aleo Devnet Image

For running a local Aleo development network with Leo and snarkOS:

```bash
# Run a minimal devnet (4 validators + 1 client)
docker run -it --rm -p 3030:3030 -p 4130:4130 \
  -v $(pwd)/data:/aleo/data \
  ghcr.io/sealance-io/aleo-devnet:v4.0.0-v4.6.0

# Run with custom devnet parameters
docker run -it --rm -p 3030:3030 -p 4130:4130 \
  -v $(pwd)/data:/aleo/data \
  ghcr.io/sealance-io/aleo-devnet:v4.0.0-v4.6.0 \
  devnet --storage /aleo/data --clear-storage --yes \
  --verbosity 4 --num-validators 4 --num-clients 2

# Run snarkOS directly instead of Leo devnet command
docker run -it --rm -p 3030:3030 -p 4130:4130 \
  --entrypoint ./snarkos \
  ghcr.io/sealance-io/aleo-devnet:v4.0.0-v4.6.0 \
  start --client --nodisplay --node 0.0.0.0:4130 \
  --network 1 --dev 0 --rest 0.0.0.0:3030

# Access Leo CLI for development
docker run -it --rm -v $(pwd):/app -w /app \
  ghcr.io/sealance-io/aleo-devnet:v4.0.0-v4.6.0 \
  new my_project
```
#### GitHub Actions Example

For CI/CD workflows, use the `setup-leo-action` instead of container images:

```yaml
name: Aleo Project Build and Test

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Leo CLI
        # TODO: update SHA after sealance-io/setup-leo-action PR #13 (Leo v4 support) merges
        uses: sealance-io/setup-leo-action@126611b39ce92d063c50da6623f8a0b08bf294dd # v1.0.0
        with:
          version: '4.0.0'

      - name: Build Leo project
        run: leo build

      - name: Run tests
        run: leo test
```

See [setup-leo-action](https://github.com/sealance-io/setup-leo-action) for more options.

## 🔄 CI/CD Automation

This repository includes automated workflows for building and publishing images, including:
- Automated version detection and builds for Leo
- Manual build triggers through GitHub Actions
- Deployment snapshot creation for custom Aleo programs

For detailed information about the CI/CD workflows, please see the [CI/CD documentation](./docs/CI.md).

### CI Checks

PRs to `main` must pass two required status checks:

- **`lint-status`** — ShellCheck for `*.sh`, Hadolint for `*.Dockerfile`
- **`security-status`** — [zizmor](https://docs.zizmor.sh/) for workflow files, [Trivy](https://trivy.dev/) for Dockerfile misconfigurations

Published image vulnerability scans (Trivy + [Grype](https://github.com/anchore/grype)) run on a weekly schedule and manual dispatch (report-only).

## 🔧 Building Images Locally

This repository provides a build script to create both image variants for any supported project.

### Prerequisites

- Docker with buildx plugin OR Podman
- GitHub Container Registry access (if pushing)

### Build Commands

```bash
# Login to GitHub Container Registry (only needed when pushing)
echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin

# Build Leo Lang image (multi-arch, push to registry)
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang

# Build Aleo Devnet image (requires leo-lang to exist in registry first)
./build-publish-image.sh --dockerfile aleo-devnet.Dockerfile --image-name aleo-devnet

# Local development build (single arch, no push — fastest)
./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang --local-arch --no-push

# See all flags: --no-latest, --no-push, --local-arch, --variant
./build-publish-image.sh --help
```

### Building Deployment Snapshots

The repository includes a script to create custom Aleo devnet images with pre-deployed programs:

```bash
# Build deployment snapshot from main branch (without pushing)
./build-publish-deployment-snapshot.sh --commit main --skip-push

# Build from specific branch/tag/commit
./build-publish-deployment-snapshot.sh --commit develop --skip-push
./build-publish-deployment-snapshot.sh --commit v1.0.0 --skip-push
./build-publish-deployment-snapshot.sh --commit abc1234 --skip-push

# Build with custom base image version
./build-publish-deployment-snapshot.sh --version v4.0.0-v4.6.0 --skip-push

# Build and push to registry (requires authentication)
./build-publish-deployment-snapshot.sh --commit main --version v4.0.0-v4.6.0

# Override required programs for verification (default: from required-programs.txt)
./build-publish-deployment-snapshot.sh --commit main --skip-push --required-programs "merkle_tree.aleo,custom.aleo"

# Get help
./build-publish-deployment-snapshot.sh --help
```

This script:
- Clones the compliant-transfer-aleo repository
- Starts a local Aleo devnet container (volume mounted at `/aleo/data` only)
- Deploys programs to the devnet
- Verifies required programs exist via REST API before stopping the container
- Captures only blockchain state (not runtime files) from the container
- Creates a new Docker image with the pre-deployed state
- Runs post-build E2E verification per-platform (amd64 + arm64)
- Retags the verified version-tag digest as `latest` (no rebuild)
- Supports multi-architecture builds (AMD64 and ARM64)
- **Fail-closed**: publish flows require a non-empty program list (from `required-programs.txt` or `--required-programs`)

### Error Recovery

If you encounter errors during pushing:

1. The script automatically retries push operations up to 3 times with a 10-second delay
2. Ensure your GitHub token has proper permissions (packages:write)
3. Check that you're logged in to the registry with `docker login` or `podman login`

## 🏗️ Customizing the Build

### Using the --variant flag

The `--variant` flag allows you to add a suffix to version tags (not `latest`), useful for building specialized versions:

```bash
# Build Leo with Node.js 24
NODE_VERSION=24 ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang --variant node24
# Produces: leo-lang:v4.0.0-node24, leo-lang:latest

# Build with custom Rust version
RUST_VERSION=1.89.0 ./build-publish-image.sh --dockerfile aleo-devnet.Dockerfile --image-name aleo-devnet --variant rust189
# Produces: aleo-devnet:v4.0.0-v4.6.0-rust189, aleo-devnet:latest
```

### Environment Variables

| Variable | Applies to | Description |
|---|---|---|
| `LEO_VERSION` | both | Leo release tag (default: `v4.0.0`) |
| `SNARKOS_VERSION` | aleo-devnet | snarkOS release tag (default: `v4.6.0`) |
| `LEO_REPO` | both | Leo Git URL (default: ProvableHQ/leo) |
| `RUST_VERSION` | both | Rust base image tag (auto-inferred from upstream `rust-toolchain.toml`) |
| `NODE_VERSION` | leo-lang | Node.js major version (default: `24`) |
| `DEBIAN_RELEASE` | both | Base image distribution (default: `trixie`) |
| `REGISTRY` | both | Container registry (default: `ghcr.io/sealance-io`) |

```bash
# Example: multiple overrides
LEO_VERSION="v4.0.0" LEO_REPO="https://github.com/your-fork/leo" NODE_VERSION=18 \
  ./build-publish-image.sh --dockerfile leo.Dockerfile --image-name leo-lang
```

## ⚠️ Compatibility Notes

The build scripts require **Docker with buildx plugin** or **Podman 3.0+** for multi-architecture support.

## 🔍 Troubleshooting

### Image Not Building for ARM64

Make sure Docker buildx is properly set up:

```bash
docker buildx ls
```

### Authentication Issues with GHCR

Ensure your GitHub token has the necessary package permissions:

```bash
echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin
```

### Permission Issues in Mounted Volumes

Add the appropriate user permissions:

```bash
docker run --rm -v $(pwd):/app -w /app --user $(id -u):$(id -g) ghcr.io/sealance-io/leo-lang:v4.0.0 leo build
```

## 📜 License

This repository is licensed under the Apache License, Version 2.0.
See the [LICENSE](./LICENSE) file for details.
