#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLE_DIR="${ROOT_DIR}/clawhub"

mkdir -p "$BUNDLE_DIR"

rsync -a --delete \
  --exclude '.git' \
  --exclude '.gitignore' \
  --exclude '.DS_Store' \
  --exclude 'clawhub' \
  --exclude 'refresh_clawhub_bundle.sh' \
  "${ROOT_DIR}/" \
  "${BUNDLE_DIR}/"

echo "Refreshed ${BUNDLE_DIR}"
