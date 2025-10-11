#!/bin/bash
# Setup script for Git hooks
# Run this once after cloning the repository

set -e

echo "🔧 Setting up Git hooks..."

# Get the project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="$PROJECT_ROOT/.githooks"
GIT_HOOKS_DIR="$PROJECT_ROOT/.git/hooks"

# Check if .githooks directory exists
if [ ! -d "$HOOKS_DIR" ]; then
    echo "❌ .githooks directory not found!"
    exit 1
fi

# Make hook scripts executable
chmod +x "$HOOKS_DIR/pre-commit"
chmod +x "$HOOKS_DIR/pre-push"

# Configure git to use our hooks directory
git config core.hooksPath "$HOOKS_DIR"

echo "✅ Git hooks configured successfully!"
echo ""
echo "Installed hooks:"
echo "  - pre-commit: Formats code, builds, and runs tests"
echo "  - pre-push: Runs comprehensive checks before pushing"
echo ""
echo "To skip hooks (not recommended):"
echo "  git commit --no-verify"
echo "  git push --no-verify"

