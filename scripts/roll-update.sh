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
STAGE_RUNTIME_DEPS_VALIDATION_PREFERENCE=(telegram discord slack whatsapp matrix)

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

build_staged_runtime_deps_variant() {
  local plugin_id="$1"
  nix build --impure --expr '
    let
      flake = builtins.getFlake (toString '"${REPO_ROOT}"');
      pkgs = import flake.inputs.nixpkgs {
        system = "x86_64-linux";
        overlays = [ flake.overlays.default ];
      };
    in
      pkgs.openclaw-gateway.override {
        stagedRuntimeDepsPluginIds = [ "'"${plugin_id}"'" ];
      }
  ' --no-link --print-out-paths
}

find_stage_runtime_deps_candidates() {
  local source_root="$1"

  node - "$source_root" <<'NODE'
const fs = require("fs");
const path = require("path");

const sourceRoot = process.argv[2];
const matches = new Set();

function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === "node_modules" || entry.name === ".git") {
      continue;
    }

    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(fullPath);
      continue;
    }

    if (entry.name !== "package.json") {
      continue;
    }

    const parsed = JSON.parse(fs.readFileSync(fullPath, "utf8"));
    if (parsed.openclaw?.bundle?.stageRuntimeDependencies === true) {
      matches.add(path.basename(path.dirname(fullPath)));
    }
  }
}

walk(sourceRoot);
for (const pluginId of Array.from(matches).sort()) {
  console.log(pluginId);
}
NODE
}

order_stage_runtime_deps_candidates() {
  local -n raw_candidates_ref="$1"
  local ordered=()
  local seen_ids=()
  local plugin_id
  local preferred_id

  for preferred_id in "${STAGE_RUNTIME_DEPS_VALIDATION_PREFERENCE[@]}"; do
    for plugin_id in "${raw_candidates_ref[@]}"; do
      if [[ "$plugin_id" == "$preferred_id" ]]; then
        ordered+=("$plugin_id")
        seen_ids+=("$plugin_id")
      fi
    done
  done

  for plugin_id in "${raw_candidates_ref[@]}"; do
    if [[ " ${seen_ids[*]} " == *" ${plugin_id} "* ]]; then
      continue
    fi
    ordered+=("$plugin_id")
  done

  printf '%s\n' "${ordered[@]}"
}

validate_staged_runtime_deps_variant() {
  local package_path="$1"
  local plugin_id="$2"

  node - "$package_path" "$plugin_id" <<'NODE'
const fs = require("fs");
const path = require("path");

const packagePath = process.argv[2];
const pluginId = process.argv[3];
const pluginRoot = path.join(packagePath, "lib", "openclaw", "dist", "extensions", pluginId);
const pluginPackageJsonPath = path.join(pluginRoot, "package.json");
const pluginNodeModulesDir = path.join(pluginRoot, "node_modules");

if (!fs.existsSync(pluginPackageJsonPath)) {
  throw new Error(`missing package.json for bundled plugin ${pluginId}`);
}
if (!fs.existsSync(pluginNodeModulesDir)) {
  throw new Error(`missing node_modules for bundled plugin ${pluginId}`);
}

const pluginPackageJson = JSON.parse(fs.readFileSync(pluginPackageJsonPath, "utf8"));
const dependencies = pluginPackageJson.dependencies ?? {};

for (const [dependencyName, requestedSpec] of Object.entries(dependencies)) {
  const dependencyPackageJsonPath = path.join(
    pluginNodeModulesDir,
    ...dependencyName.split("/"),
    "package.json",
  );

  if (!fs.existsSync(dependencyPackageJsonPath)) {
    throw new Error(`missing staged dependency ${dependencyName} for bundled plugin ${pluginId}`);
  }

  const installedVersion = JSON.parse(fs.readFileSync(dependencyPackageJsonPath, "utf8")).version;
  if (/^[0-9]+\.[0-9]+\.[0-9]+(?:[-+].+)?$/.test(requestedSpec) && installedVersion !== requestedSpec) {
    throw new Error(
      `version mismatch for ${dependencyName} in bundled plugin ${pluginId}: expected ${requestedSpec}, got ${installedVersion}`,
    );
  }
}
NODE
}

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
UPSTREAM_SRC_DIR="${TMP}/openclaw-${NEW_REV}"

log "Downloading upstream source..."
curl -fSL --max-time 120 \
  "https://github.com/openclaw/openclaw/archive/${NEW_REV}.tar.gz" \
  | tar xz -C "$TMP"

ensure_pruner_deps
log "Pruning lockfile..."
node "$PRUNER_DIR/prune.mjs" "$UPSTREAM_SRC_DIR" "$TMP/pruned"
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

  mapfile -t RAW_STAGE_CANDIDATES < <(find_stage_runtime_deps_candidates "$UPSTREAM_SRC_DIR")
  mapfile -t STAGE_CANDIDATES < <(order_stage_runtime_deps_candidates RAW_STAGE_CANDIDATES)
  if [[ ${#STAGE_CANDIDATES[@]} -eq 0 ]]; then
    log "No bundled plugins currently request build-time runtime-deps staging."
  else
    STAGED_VARIANT_OK=false
    for plugin_id in "${STAGE_CANDIDATES[@]}"; do
      if [[ ! -d "${PKG_PATH}/lib/openclaw/dist/extensions/${plugin_id}" ]]; then
        warn "Skipping staged runtime-deps validation for missing packaged plugin ${plugin_id}"
        continue
      fi
      if [[ -d "${PKG_PATH}/lib/openclaw/dist/extensions/${plugin_id}/node_modules" ]]; then
        warn "Default package unexpectedly staged runtime deps for ${plugin_id}"
        exit 1
      fi

      if STAGED_VARIANT_PATH="$(build_staged_runtime_deps_variant "$plugin_id")"; then
        if [[ -d "${STAGED_VARIANT_PATH}/lib/openclaw/dist/extensions/${plugin_id}/node_modules" ]]; then
          validate_staged_runtime_deps_variant "$STAGED_VARIANT_PATH" "$plugin_id"
          log "Validated staged runtime deps for bundled plugin ${plugin_id}"
          STAGED_VARIANT_OK=true
          break
        fi
        warn "Missing staged runtime deps for ${plugin_id} in ${STAGED_VARIANT_PATH}"
      else
        warn "Staged runtime-deps build failed for ${plugin_id}; trying next candidate"
      fi
    done

    if [[ "$STAGED_VARIANT_OK" != "true" ]]; then
      warn "Failed to validate build-time staged runtime deps for bundled plugins: ${STAGE_CANDIDATES[*]}"
      exit 1
    fi
  fi

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
