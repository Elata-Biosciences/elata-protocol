#!/usr/bin/env bash
set -euo pipefail

PINNED_VERSION="v1.4.2"

if ! command -v foundryup >/dev/null 2>&1; then
  echo "⚠️  foundryup not found; installing Foundry toolchain..."
  curl -L https://foundry.paradigm.xyz | bash
  source "$HOME/.bashrc" 2>/dev/null || true
  source "$HOME/.zshrc" 2>/dev/null || true
fi

echo "🔧 Pinning Foundry toolchain to ${PINNED_VERSION}"
foundryup -v "${PINNED_VERSION}" || true

# Ensure we use the ~/.foundry/bin toolchain
export PATH="$HOME/.foundry/bin:$PATH"

echo "🧪 which forge: $(command -v forge || true)"
echo "🧪 forge --version:"
forge --version || true

if forge --version 2>/dev/null | grep -q "${PINNED_VERSION}"; then
  echo "✅ Foundry pinned to ${PINNED_VERSION}"
else
  echo "⚠️  Foundry not at ${PINNED_VERSION}. If brew-installed forge is shadowing, remove it or ensure ~/.foundry/bin precedes it in PATH."
fi


