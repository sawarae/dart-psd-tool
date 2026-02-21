#!/usr/bin/env bash
# Download and extract blend mode test fixtures from GitHub release v0.0.1.
# Idempotent: skips download if fixtures already exist.
#
# Usage: bash tool/download_fixtures.sh

set -euo pipefail

REPO="sawarae/dart-psd-tool"
TAG="v0.0.1"
ASSET="blend-mode-test-results.zip"
FIXTURE_DIR="test/fixtures/blend-mode-test"

# Change to repo root
cd "$(git rev-parse --show-toplevel)"

# Skip if fixtures already exist
if [ -d "$FIXTURE_DIR/results" ] && [ -d "$FIXTURE_DIR/psd" ]; then
  echo "Fixtures already present at $FIXTURE_DIR — skipping download."
  exit 0
fi

echo "Downloading $ASSET from release $TAG..."
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

gh release download "$TAG" \
  --repo "$REPO" \
  --pattern "$ASSET" \
  --dir "$TMP_DIR"

echo "Extracting to $FIXTURE_DIR..."
mkdir -p "$FIXTURE_DIR"
unzip -qo "$TMP_DIR/$ASSET" -d "$FIXTURE_DIR"

echo "Done. Fixtures at $FIXTURE_DIR/"
ls "$FIXTURE_DIR/"
