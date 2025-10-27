#!/usr/bin/env bash
set -euo pipefail

PINNED_VERSION="v1.1.0"

if ! command -v foundryup >/dev/null 2>&1; then
  echo "⚠️  foundryup not found; installing Foundry toolchain..."
  curl -L https://foundry.paradigm.xyz | bash
  source "$HOME/.bashrc" 2>/dev/null || true
  source "$HOME/.zshrc" 2>/dev/null || true
fi

echo "🔧 Pinning Foundry toolchain to ${PINNED_VERSION}"
foundryup -v "${PINNED_VERSION}"

echo "🧪 forge --version:"
forge --version

echo "✅ Foundry pinned to ${PINNED_VERSION}"


