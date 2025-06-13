# 🔄 CI/CD Workflows

This repository uses GitHub Actions to automate the building and publishing of Docker images.

## Automated Version Detection

A weekly workflow checks for new releases of Leo and Amareleo Chain:

- Runs every Monday at 2:30 AM UTC
- Scans both upstream repositories for new release tags
- Only processes versions that meet minimum requirements:
  - Leo: v2.4.1 or higher
  - Amareleo Chain: v2.1.0 or higher
- Compares against existing images in the registry to avoid rebuilding
- Automatically triggers builds for new versions

## Build Workflows

The build system consists of three primary workflows:

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

## Manual Builds

You can manually trigger builds through the GitHub Actions interface:

1. Navigate to the "Actions" tab in the repository
2. Select the "Build Docker Images" workflow
3. Click "Run workflow"
4. Fill in the required parameters:
   - Image name (`leo-lang` or `amareleo-chain`)
   - Version tag
   - Other optional settings

This is useful for testing or building specific versions that might not be automatically detected.

## How It Works

1. The weekly check uses GitHub API to fetch release tags from upstream
2. It normalizes version strings for proper semantic comparison
3. Tags below the minimum version threshold are filtered out
4. Existing registry tags are checked to avoid duplicate builds
5. For each new qualifying tag, a build workflow is triggered
6. Images are built and published to the GitHub Container Registry

The entire process ensures new versions are automatically built while maintaining strict version requirements and preventing redundant builds.