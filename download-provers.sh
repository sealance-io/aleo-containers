#!/bin/bash
set -euo pipefail

# Configuration
DEST_DIR="/root/.aleo/resources/"
BASE_URL="https://parameters.aleo.org/mainnet"
MAX_PARALLEL=4  # Number of parallel downloads

# Create destination directory
mkdir -p "$DEST_DIR"
cd "$DEST_DIR"

# List of files to download
FILES=(
  "powers-of-beta-16.usrs.84631bc"
  "shifted-powers-of-beta-16.usrs.d99bcb3"
  "powers-of-beta-17.usrs.7c27308"
  "shifted-powers-of-beta-17.usrs.2025178"
  "powers-of-beta-18.usrs.7a12bcb"
  "shifted-powers-of-beta-18.usrs.9a1859e"
  "powers-of-beta-19.usrs.e535d44"
  "shifted-powers-of-beta-19.usrs.662e343"
)

# Create a temporary directory to track download status
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

# Process files in batches for reliable parallelization
total_files=${#FILES[@]}
for ((i=0; i<total_files; i+=MAX_PARALLEL)); do
  # Determine batch size (last batch may be smaller)
  batch_size=$MAX_PARALLEL
  if ((i + batch_size > total_files)); then
    batch_size=$((total_files - i))
  fi
  
  # Start downloads for this batch
  for ((j=0; j<batch_size; j++)); do
    index=$((i + j))
    file="${FILES[index]}"
    echo "Downloading $file..."
    
    # Start download in background with status tracking
    (
      if curl -fsSL "$BASE_URL/$file" -o "$file"; then
        echo "✓ Downloaded $file successfully"
        touch "$tmp_dir/$index.success"
      else
        echo "✗ Failed to download $file (error code: $?)" >&2
        touch "$tmp_dir/$index.failed"
      fi
    ) &
  done
  
  # Wait for all downloads in this batch to complete
  wait
done

# Check for any failed downloads
failed=0
for ((i=0; i<total_files; i++)); do
  if [ -f "$tmp_dir/$i.failed" ]; then
    failed=1
    echo "Download failed for ${FILES[i]}" >&2
  fi
done

if [ $failed -ne 0 ]; then
  echo "One or more downloads failed" >&2
  exit 1
fi

echo "All files downloaded successfully"