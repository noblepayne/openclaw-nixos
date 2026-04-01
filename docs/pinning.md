# Pinning and updates

## What's pinned

| Artifact | Location | Format |
|----------|----------|--------|
| OpenClaw source | `flake.lock` → `inputs.openclaw` | GitHub rev + narHash |
| Pruned lockfile | `pnpm-lock-pruned.yaml` | pnpm lockfile v9 |
| pnpmDepsHash | `flake.nix` | Nix hash (sha256-...) |
| Nixpkgs | `flake.lock` → `inputs.nixpkgs` | GitHub rev + narHash |

## How to update

### Full update (new upstream release)

```bash
cd ~/src/openclaw-nixos

# 1. Pull new openclaw source
nix flake update openclaw

# 2. Regenerate pruned lockfile
#    Assumes openclaw source is checked out at OPENCLAW_DIR (default: /dev/shm/openclaw)
OPENCLAW_DIR=/path/to/openclaw scripts/update-pin.sh

# 3. Build (will fail on hash mismatch)
nix build .#openclaw-gateway 2>&1 | grep 'got:'
# Output: got:    sha256-<real-hash>

# 4. Update the hash in flake.nix
#    Edit pnpmDepsHash = "sha256-<real-hash>";

# 5. Verify build
nix build .#openclaw-gateway

# 6. Commit
git add -A && git commit -m "bump openclaw to $(jq -r '.nodes.openclaw.locked.rev' flake.lock | head -c 8)"
```

### Nixpkgs only

```bash
nix flake update nixpkgs
```

### Just re-prune the lockfile (same upstream version)

```bash
OPENCLAW_DIR=/path/to/openclaw node _tools/lockfile-pruner/prune.mjs $OPENCLAW_DIR .
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

## Why three separate pins?

1. **flake.lock (openclaw SHA)**: Tracks upstream source. Updated by `nix flake update`.
2. **pnpm-lock-pruned.yaml**: Our filtered lockfile. Must be regenerated when upstream changes their lockfile.
3. **pnpmDepsHash**: Hash of the fetched pnpm store for our pruned lockfile. Must match exactly or Nix refuses to build.

All three must be consistent. The `update-pin.sh` script handles #1 and #2. #3 is manual (you verify the build).
