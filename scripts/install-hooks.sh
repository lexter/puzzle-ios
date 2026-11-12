#!/usr/bin/env bash
# Points git at the versioned hooks in .githooks (pre-commit: lint, pre-push: build).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
git config core.hooksPath .githooks
chmod +x .githooks/*
echo "Git hooks installed from .githooks"
