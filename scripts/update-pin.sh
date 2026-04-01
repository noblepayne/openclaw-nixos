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

cd "$REPO_ROOT"

echo ">> Updating openclaw flake input..."
if [ -n "${1:-}" ]; then
  nix flake update openclaw --override-input openclaw "github:openclaw/openclaw/$1"
else
  nix flake update openclaw
fi

echo ">> Getting openclaw revision..."
REV=$(jq -r '.nodes.openclaw.locked.rev' flake.lock)
echo "   Rev: $REV"

echo ">> Downloading upstream source..."
TMPDIR=$(mktemp -d)
curl -fSL "https://github.com/openclaw/openclaw/archive/${REV}.tar.gz" | tar xz -C "${TMPDIR}"
UPSTREAM="${TMPDIR}/openclaw-${REV}"

echo ">> Regenerating pruned lockfile..."
node _tools/lockfile-pruner/prune.mjs "$UPSTREAM" "$REPO_ROOT"
mv "$REPO_ROOT/pnpm-lock.yaml" "$REPO_ROOT/pnpm-lock-pruned.yaml"

echo ">> Cleanup..."
rm -rf "$TMPDIR"

echo ">> Done!"
echo ""
echo "Next steps:"
echo "  1. Set flake.nix pnpmDepsHash to \"\" (empty)"
echo "  2. nix build .#openclaw-gateway.pnpmDeps 2>&1 | grep 'got:'"
echo "  3. Copy the 'got:' hash into flake.nix pnpmDepsHash"
echo "  4. nix build .#openclaw-gateway (verify it builds)"
echo "  5. ./result/bin/openclaw --version (smoke test)"
