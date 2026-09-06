#!/usr/bin/env bash
# Lance shellcheck sur les scripts puis les tests bats.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
shellcheck scripts/*.sh
bats tests/
