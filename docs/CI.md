# 🔄 CI/CD Workflows

This repository uses GitHub Actions to automate the building and publishing of Docker images.

## Automated Version Detection

A weekly workflow checks for new releases of Leo:

- Runs every Monday at 2:30 AM UTC
- Scans the upstream Leo repository for new release tags
- Only processes versions that meet minimum requirements (Leo: v2.4.1 or higher)
- Compares against existing images in the registry to avoid rebuilding
- Automatically triggers builds for new versions

## Build Workflows

The build system consists of four primary workflows:

1. **Reusable Build Workflow** (`build-publish-image.yml`)
   - Core functionality for building and pushing images
   - Handles multi-architecture builds (AMD64/ARM64)
   - Configurable through parameters

2. **Callable Interface** (`build-images.yml`)
   - Entry point for manual builds and automated triggers
   - Validates input parameters
   - Provides a user-friendly interface

3. **Update Detection** (`check-updates.yml`)
   - Monitors upstream repositories for new versions
   - Applies semantic versioning filters
   - Triggers builds for new releases

4. **Deployment Snapshot Workflow** (`build-publish-deployment-snapshot.yml`)
   - Creates custom Aleo devnet images with pre-deployed programs
   - Clones and deploys programs from compliant-transfer-aleo repository
   - Captures blockchain state after deployment
   - Builds multi-architecture images with the deployed state

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