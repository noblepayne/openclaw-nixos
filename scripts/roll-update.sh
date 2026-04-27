#!/usr/bin/env bash
set -euo pipefail

# roll-update.sh — Update OpenClaw to latest stable, build, validate, optionally push.
#
# Usage:
#   scripts/roll-update.sh              # dry run: update, build, test
#   scripts/roll-update.sh --push       # update, build, test, commit + push current branch
#   scripts/roll-update.sh --rev <sha>  # pin to specific revision
#   scripts/roll-update.sh --tag <tag>  # pin to specific stable tag
#   scripts/roll-update.sh --no-build   # update + hash only (skip build + test)
#   scripts/roll-update.sh --version    # just check for a new version, exit accordingly
#
# Exit codes:
#   0 — success (pushed if --push, otherwise all-local clean)
#   1 — build or test failure
#   2 — invalid usage

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PUSH=false
REV=""
TAG=""
DO_BUILD=true
VERSION_CHECK=false
INPUT_NAME="openclaw"
LOCKFILE_OUT="$REPO_ROOT/pnpm-lock-pruned.yaml"
PRUNER_DIR="$REPO_ROOT/_tools/lockfile-pruner"

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

log() { echo ">> $1"; }
warn() { echo "!! $1" >&2; }

resolve_latest_stable_tag() {
  gh api repos/openclaw/openclaw/releases --paginate \
    | jq -r -s '
        add
        | map(select(.draft == false and .prerelease == false))
        | sort_by(.published_at)
        | last
        | .tag_name
      '
}

resolve_tag_commit() {
  local tag="$1"
  local repo_url="https://github.com/openclaw/openclaw.git"
  local line
  line="$(git ls-remote --tags "$repo_url" "refs/tags/${tag}^{}" | awk "{print \$1}" || true)"
  if [[ -n "$line" ]]; then
    printf '%s\n' "$line"
    return 0
  fi
  git ls-remote --tags "$repo_url" "refs/tags/${tag}" | awk '{print $1}'
}

ensure_pruner_deps() {
  if [[ ! -f "$PRUNER_DIR/package-lock.json" ]]; then
    warn "Missing $PRUNER_DIR/package-lock.json"
    exit 1
  fi
  log "Installing lockfile-pruner dependencies from package-lock.json"
  (cd "$PRUNER_DIR" && npm ci --ignore-scripts --no-audit --no-fund)
}

update_hash() {
  local hash="$1"
  perl -0pi -e 's|pnpmDepsHash = "[^"]*";|pnpmDepsHash = "'"$hash"'";|' "$REPO_ROOT/flake.nix"
}

# Track temporary resources for cleanup
TMPDIRS=()
cleanup() {
  for d in "${TMPDIRS[@]}"; do
    rm -rf "$d" 2>/dev/null || true
  done
}
trap cleanup EXIT

if [[ -z "$REV" ]]; then
  if [[ -z "$TAG" ]]; then
    TAG="$(resolve_latest_stable_tag)"
  fi
  if [[ -z "$TAG" || "$TAG" == "null" ]]; then
    warn "Failed to resolve latest stable OpenClaw tag"
    exit 1
  fi
  REV="$(resolve_tag_commit "$TAG")"
fi

if [[ -z "$REV" ]]; then
  warn "Failed to resolve OpenClaw revision"
  exit 1
fi

# --- Phase 1: Update pin ---

OLD_REV="$(jq -r --arg input "$INPUT_NAME" '.nodes[$input].locked.rev' flake.lock)"

log "Updating ${INPUT_NAME} to ${TAG:-$REV}"
nix flake lock \
  --update-input "$INPUT_NAME" \
  --override-input "$INPUT_NAME" "github:openclaw/openclaw/$REV"

NEW_REV="$(jq -r --arg input "$INPUT_NAME" '.nodes[$input].locked.rev' flake.lock)"

if [[ "$OLD_REV" == "$NEW_REV" ]]; then
  if [[ "$VERSION_CHECK" == "true" ]]; then
    echo "up-to-date"
  else
    log "Already at latest. Nothing to do."
  fi
  exit 0
fi

# --- Phase 2: Prune lockfile from actual upstream tarball ---

log "openclaw: ${OLD_REV:0:7} → ${NEW_REV:0:7}"

TMP=$(mktemp -d)
TMPDIRS+=("$TMP")

log "Downloading upstream source..."
curl -fSL --max-time 120 \
  "https://github.com/openclaw/openclaw/archive/${NEW_REV}.tar.gz" \
  | tar xz -C "$TMP"

ensure_pruner_deps
log "Pruning lockfile..."
node "$PRUNER_DIR/prune.mjs" "${TMP}/openclaw-${NEW_REV}" "$TMP/pruned"
mv "$TMP/pruned/pnpm-lock.yaml" "$LOCKFILE_OUT"

# --- Phase 3: Get pnpmDepsHash ---

log "Fetching pnpmDepsHash..."
update_hash "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

set +e
HASH="$(
  nix build .#openclaw-gateway.pnpmDeps 2>&1 \
    | tee /dev/stderr \
    | grep -E '^[[:space:]]*got:' \
    | awk '{print $NF}' \
    | tail -n 1
)"
set -e

if [[ -z "$HASH" ]]; then
  warn "Failed to extract pnpmDepsHash."
  exit 1
fi

log "pnpmDepsHash: $HASH"
update_hash "$HASH"

# --- Phase 4: Full build + validation ---

VERSION="unknown"
if [[ "$DO_BUILD" == "true" ]]; then
  log "Building openclaw-gateway..."
  nix build .#openclaw-gateway --no-link -L

  log "Running validation..."
  VERSION="$(nix run .#openclaw-gateway -- --version 2>&1 || true)"
  log "openclaw --version: $VERSION"

  if [[ -z "$VERSION" || "$VERSION" == "unknown" ]]; then
    warn "openclaw --version not usable"
    exit 1
  fi

  PKG_PATH="$(nix build .#openclaw-gateway --print-out-paths --no-link)"
  for subdir in dist extensions node_modules/.pnpm; do
    if [[ ! -d "${PKG_PATH}/lib/openclaw/${subdir}" ]]; then
      warn "Missing critical path: ${PKG_PATH}/lib/openclaw/${subdir}"
      exit 1
    fi
  done

  log "All validation checks passed."
else
  log "Skipping build (--no-build)."
fi

# --- Phase 5: Commit + push (if --push) ---

if [[ "$PUSH" == "true" ]]; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD)
  if [[ "$BRANCH" == "HEAD" ]]; then
    warn "--push requires a named branch"
    exit 2
  fi

  MSG="chore: bump openclaw to ${TAG:-${NEW_REV:0:7}}"
  git add flake.lock pnpm-lock-pruned.yaml flake.nix

  # Only commit if there are changes
  if git diff --cached --quiet; then
    log "No changes to commit."
    exit 0
  fi

  git commit -m "$MSG"

  if ! git push origin "$BRANCH"; then
    warn "Push failed. The local commit remains; retry after syncing."
    exit 1
  fi

  log "Pushed OpenClaw roll update to ${BRANCH}."
else
  log "Dry run complete. Run again with --push to commit."
fi

log "Done."
