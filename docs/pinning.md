# Pinning and updates

## What's pinned

| Artifact | Location | Format |
|----------|----------|--------|
| OpenClaw source pin | `flake.nix` → `inputs.openclaw.url` | GitHub ref (authoritative) |
| Resolved source | `flake.lock` → `inputs.openclaw.locked` | GitHub rev + narHash |
| Pruned lockfile | `pnpm-lock-pruned.yaml` | pnpm lockfile v9 |
| pnpmDepsHash | `flake.nix` | Nix hash (sha256-...) |
| Nixpkgs | `flake.lock` → `inputs.nixpkgs` | GitHub rev + narHash |

## How to update

### Full update (new upstream release)

```bash
cd ~/src/openclaw-nixos

# 1. Pin authoritative URL in flake.nix
#    Edit inputs.openclaw.url to the new tag (e.g. v2026.5.6)

# 2. Resolve lockfile from authoritative pin
nix flake lock --update-input openclaw

# 3. Prune lockfile
#    Download raw upstream source and run the pruner
TMPDIR=$(mktemp -d)
curl -fSL "https://github.com/openclaw/openclaw/archive/$(jq -r '.nodes.openclaw.locked.rev' flake.lock).tar.gz" \
  | tar xz -C "$TMPDIR"
node _tools/lockfile-pruner/prune.mjs "$TMPDIR/openclaw-$(jq -r '.nodes.openclaw.locked.rev' flake.lock)" .
mv pnpm-lock.yaml pnpm-lock-pruned.yaml

# 4. Capture pnpmDepsHash
#    Set placeholder first
perl -0pi -e 's|pnpmDepsHash = "[^"]*";|pnpmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";|' flake.nix
nix build .#openclaw-gateway.pnpmDeps 2>&1 | grep 'got:'

#    Update with the real hash
perl -0pi -e 's|pnpmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";|pnpmDepsHash = "sha256-<got-value>";|' flake.nix

# 5. Verify
nix build .#openclaw-gateway
nix run .#openclaw-gateway -- --version

# 6. Commit
git add flake.nix flake.lock pnpm-lock-pruned.yaml && git commit -m "chore: bump openclaw to $(jq -r '.nodes.openclaw.locked.rev' flake.lock | head -c 8)"
```

### Automated alternative: `scripts/roll-update.sh`

The repo includes a full automation script that covers updates, pruning, hash capture, and builds:

```bash
# Dry run (builds but doesn't commit)
./scripts/roll-update.sh --tag v2026.5.6

# With push (auto-commits and pushes current branch)
./scripts/roll-update.sh --tag v2026.5.6 --push

# Pin to a specific commit SHA
./scripts/roll-update.sh --rev <sha>
```

### Nixpkgs only

```bash
nix flake update nixpkgs
```

### Just re-prune the lockfile (same upstream version)

```bash
node _tools/lockfile-pruner/prune.mjs /path/to/openclaw-source .
mv pnpm-lock.yaml pnpm-lock-pruned.yaml
# Rebuild to check hash
nix build .#openclaw-gateway 2>&1 | grep 'got:'
```

## Hash format

`pnpmDepsHash` uses the SRI format: `sha256-<base64>`.

When you see a hash mismatch error:
```
error: hash mismatch in fixed-output derivation:
  got:    sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
  wanted: sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=
```

Copy the `got:` value into `flake.nix`.

## pnpm config mismatch

If the build fails with `ERR_PNPM_LOCKFILE_CONFIG_MISMATCH`:

This happens when the upstream `package.json` `pnpm.overrides` block has changed since the last version bump. The pruned lockfile preserves these overrides from the upstream source, so re-running the pruner on the fresh 5.6 source resolves it — there is no manual edit needed.

## Why four separate pins?

`AGENTS.md` defines the authoritative ordering:

1. **`flake.nix` URL** — the authoritative pin. Always update this first.
2. **`flake.lock`** — resolved from `flake.nix`. Never hand-edit.
3. **`pnpm-lock-pruned.yaml`** — filtered lockfile. Regenerate via pruner.
4. **`pnpmDepsHash`** — hash of the fetched pnpm store. Must match exactly.

All four must be consistent, and `flake.nix` is the source of truth.
