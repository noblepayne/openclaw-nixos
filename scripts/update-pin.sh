#!/usr/bin/env bash
set -euo pipefail

# update-pin.sh — Update the openclaw upstream pin and regenerate the pruned lockfile.
#
# Usage:
#   scripts/update-pin.sh                 # Update to latest openclaw main
#   scripts/update-pin.sh <rev>           # Update to specific rev
#
# After running, do:
#   nix build .#openclaw-gateway 2>&1 | grep 'got:'
#   # Copy the 'got:' hash into flake.nix pnpmDepsHash

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OPENCLAW_DIR="${OPENCLAW_DIR:-/dev/shm/openclaw}"

cd "$REPO_ROOT"

echo ">> Updating openclaw flake input..."
if [ -n "${1:-}" ]; then
  nix flake update openclaw --override-input openclaw "github:openclaw/openclaw/$1"
else
  nix flake update openclaw
fi

echo ">> Getting openclaw source path..."
OPENCLAW_SRC=$(nix eval --raw '.#openclaw.outPath' 2>/dev/null || true)
if [ -z "$OPENCLAW_SRC" ]; then
  # Fallback: parse from flake.lock
  OPENCLAW_SRC=$(jq -r '.nodes.openclaw.locked.rev' flake.lock)
  echo "   Rev: $OPENCLAW_SRC"
fi

echo ">> Regenerating pruned lockfile..."
node _tools/lockfile-pruner/prune.mjs "$OPENCLAW_DIR" "$REPO_ROOT"
mv "$REPO_ROOT/pnpm-lock.yaml" "$REPO_ROOT/pnpm-lock-pruned.yaml"

echo ">> Done!"
echo ""
echo "Next steps:"
echo "  1. nix build .#openclaw-gateway 2>&1 | grep 'got:'"
echo "  2. Copy the 'got:' hash into flake.nix pnpmDepsHash"
echo "  3. nix build .#openclaw-gateway  (verify it builds)"
