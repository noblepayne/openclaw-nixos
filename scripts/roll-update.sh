#!/usr/bin/env bash
set -euo pipefail

# roll-update.sh — Update openclaw to latest, build, test, optionally push.
#
# Usage:
#   scripts/roll-update.sh              # dry run: update, build, test
#   scripts/roll-update.sh --push       # update, build, test, commit + push to main
#   scripts/roll-update.sh --rev <sha>  # pin to specific revision
#   scripts/roll-update.sh --tag <tag>  # pin to specific tag (e.g. v2026.4.1)
#   scripts/roll-update.sh --no-build   # update + hash only (skip build + test)
#   scripts/roll-update.sh --version    # just check for a new version, exit accordingly
#
# Exit codes:
#   0 — success (pushed if --push, otherwise all-local clean)
#   1 — build or test failure
#   2 — no changes to push (already at latest)

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PUSH=false
REV=""
TAG=""
DO_BUILD=true
VERSION_CHECK=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push)        PUSH=true ;;
    --rev)         REV="$2"; shift 2 ;;
    --tag)         TAG="$2"; shift 2 ;;
    --no-build)    DO_BUILD=false ;;
    --version)     VERSION_CHECK=true ;;
    *)             echo "Unknown flag: $1"; exit 2 ;;
  esac
done

# Resolve --tag to SHA
if [[ -n "$TAG" ]]; then
  TAG_SHA=$(curl -sf --max-time 30 \
    "https://api.github.com/repos/openclaw/openclaw/git/ref/tags/${TAG}" \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['object']['sha'])" 2>/dev/null) || true
  if [[ -z "${TAG_SHA:-}" ]]; then
    echo "!! Failed to resolve tag: $TAG" >&2
    exit 1
  fi
  REV="$TAG_SHA"
fi

log() { echo ">> $1"; }
warn() { echo "!! $1" >&2; }

# Track temporary resources for cleanup
TMPDIRS=()
cleanup() {
  for d in "${TMPDIRS[@]}"; do
    rm -rf "$d" 2>/dev/null || true
  done
}
trap cleanup EXIT

# --- Phase 1: Update pin ---

OLD_REV=$(jq -r '.nodes.openclaw.locked.rev' flake.lock)

if [[ -n "${REV:-}" ]]; then
  log "Updating openclaw to ${REV:0:7}"
  nix flake update openclaw --override-input openclaw "github:openclaw/openclaw/$REV"
else
  log "Updating openclaw to latest main"
  nix flake update openclaw
fi

NEW_REV=$(jq -r '.nodes.openclaw.locked.rev' flake.lock)

if [[ "$OLD_REV" == "$NEW_REV" ]]; then
  if [[ "$VERSION_CHECK" == "true" ]]; then
    echo "up-to-date"
  else
    log "Already at latest. Nothing to do."
  fi
  exit 2
fi

# --- Phase 2: Prune lockfile from actual upstream tarball ---

log "openclaw: ${OLD_REV:0:7} → ${NEW_REV:0:7}"

TMP=$(mktemp -d)
TMPDIRS+=("$TMP")

log "Downloading upstream source..."
curl -fSL --max-time 120 \
  "https://github.com/openclaw/openclaw/archive/${NEW_REV}.tar.gz" \
  | tar xz -C "$TMP"

log "Pruning lockfile..."
node _tools/lockfile-pruner/prune.mjs "${TMP}/openclaw-${NEW_REV}" "$REPO_ROOT"
mv "$REPO_ROOT/pnpm-lock.yaml" "$REPO_ROOT/pnpm-lock-pruned.yaml"

# --- Phase 3: Get pnpmDepsHash ---

log "Fetching pnpmDepsHash..."
sed -i 's/pnpmDepsHash = "[^"]*"/pnpmDepsHash = ""/' flake.nix

HASH=$(nix build .#openclaw-gateway.pnpmDeps 2>&1 | tee /dev/stderr | grep 'got:' | awk '{print $NF}') || true

if [[ -z "$HASH" ]]; then
  warn "Failed to extract pnpmDepsHash."
  exit 1
fi

log "pnpmDepsHash: $HASH"
sed -i "s|pnpmDepsHash = \"\"|pnpmDepsHash = \"${HASH}\"|" flake.nix

# --- Phase 4: Full build + validation ---

VERSION="unknown"
if [[ "$DO_BUILD" == "true" ]]; then
  log "Building openclaw-gateway..."
  nix build .#openclaw-gateway 2>&1 | tee /dev/stderr

  log "Running validation..."
  VERSION=$(./result/bin/openclaw --version 2>&1) || true
  log "openclaw --version: $VERSION"

  if [[ -z "$VERSION" || "$VERSION" == "unknown" ]]; then
    warn "openclaw --version not usable"
    exit 1
  fi

  # Check critical paths in the built artifact
  for subdir in dist plugins extensions node_modules/.pnpm; do
    if [[ ! -d "result/lib/openclaw/${subdir}" ]]; then
      warn "Missing critical path: result/lib/openclaw/${subdir}"
      exit 1
    fi
  done

  log "All validation checks passed."
else
  log "Skipping build (--no-build)."
fi

# --- Phase 6: Commit + push (if --push) ---

if [[ "$PUSH" == "true" ]]; then
  log "Committing to main..."

  BRANCH=$(git rev-parse --abbrev-ref HEAD)
  if [[ "$BRANCH" != "main" ]]; then
    warn "Not on main (currently on $BRANCH). --push requires main."
    exit 2
  fi

  MSG="chore: bump openclaw to ${NEW_REV:0:7} (${VERSION:-updated})"
  git add flake.lock pnpm-lock-pruned.yaml flake.nix

  # Only commit if there are changes
  if git diff --cached --quiet; then
    log "No changes to commit."
    exit 2
  fi

  git commit -m "$MSG"

  if ! git push origin main --force-with-lease; then
    warn "Push failed. The local commit remains; retry after syncing."
    exit 1
  fi

  log "Pushed to main."
else
  log "Dry run complete. Run again with --push to commit."
fi

log "Done."
