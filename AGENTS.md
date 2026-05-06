# OpenClaw NixOS Agent Protocol

## Maintenance Workflow: Version Bumps

When bumping the upstream OpenClaw version, the repository state must remain synchronized. The authoritative source of truth is `flake.nix`; `flake.lock` is derived from it.

### Canonical Bump Sequence

1. **Update Flake Input (Authoritative):** Modify `flake.nix` `inputs.openclaw.url` to the desired tag or commit (e.g. `v2026.5.6`).
2. **Synchronize Lockfile:** Run `nix flake lock --update-input openclaw` to resolve the version and update `flake.lock`.
3. **Prune Lockfile:**
    - Download the raw `pnpm-lock.yaml` from the new upstream version URL.
    - Run the pruner: `node _tools/lockfile-pruner/prune.mjs <extracted_source_dir>`
    - Replace `pnpm-lock-pruned.yaml` with the output.
4. **Update Hash:**
    - Set `pnpmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="` as a placeholder in `flake.nix`.
    - Run `nix build .#openclaw-gateway.pnpmDeps 2>&1 | grep 'got:'`.
    - Update `pnpmDepsHash` with the captured SRI hash.
5. **Verify:**
    - `nix build .#openclaw-gateway`
    - `nix run .#openclaw-gateway -- --version`
6. **Commit:** Commit `flake.nix`, `flake.lock`, and `pnpm-lock-pruned.yaml` together.

### Principles

- **No Manual Forcing:** Never manually edit `flake.lock` without a corresponding `flake.nix` URL change. Always update `flake.nix` first.
- **Verification First:** If a build fails with `ERR_PNPM_LOCKFILE_CONFIG_MISMATCH`, the `pnpm.overrides` block in the lockfile likely needs re-generation from the new upstream source. Re-prune before investigating Nix build logic.
- **Always Verify Hashes:** A passing build proves code works, but mismatched hashes prove nothing. Always verify `flake.nix` and `flake.lock` are in sync before building.

## Project Structure Overview

| Artifact | Location | Format |
|----------|----------|--------|
| OpenClaw source pin | `flake.nix` → `inputs.openclaw.url` | GitHub ref |
| Resolved source | `flake.lock` → `inputs.openclaw.locked` | GitHub rev + narHash |
| Pruned lockfile | `pnpm-lock-pruned.yaml` | pnpm lockfile v9 |
| pnpm deps hash | `flake.nix` → `pnpmDepsHash` | Nix hash (sha256-...) |
| Nixpkgs | `flake.lock` → `inputs.nixpkgs` | GitHub rev + narHash |
