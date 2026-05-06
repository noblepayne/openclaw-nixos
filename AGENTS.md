# OpenClaw NixOS Agent Protocol

## Maintenance Workflow: Version Bumps

When bumping the upstream OpenClaw version, the repository state must remain synchronized. The authoritative source of truth is `flake.nix`; `flake.lock` is derived from it.

### Canonical Bump Sequence

1. **Update Flake Input (Authoritative):** Modify `flake.nix` `inputs.openclaw.url` to the desired tag or commit (e.g. `v2026.5.6`).

2. **Synchronize Lockfile:** Run `nix flake lock --update-input openclaw` to resolve the version and update `flake.lock`.

3. **Prune Lockfile:**
    - Extract the source tarball from the commit resolved in `flake.lock`:
      ```bash
      REV=$(jq -r '.nodes.openclaw.locked.rev' flake.lock)
      TMPDIR=$(mktemp -d)
      curl -fSL "https://github.com/openclaw/openclaw/archive/${REV}.tar.gz" | tar xz -C "$TMPDIR"
      ```
    - Run the pruner against that exact source:
      ```bash
      node _tools/lockfile-pruner/prune.mjs "$TMPDIR/openclaw-${REV}" /tmp/pruned
      cp /tmp/pruned/pnpm-lock.yaml pnpm-lock-pruned.yaml
      ```
    - **Verify overrides** match the new version before proceeding:
      ```bash
      # Should show the new override values (e.g. axios: 1.16.0, @anthropic-ai/sdk: 0.93.0)
      grep '@anthropic-ai/sdk' pnpm-lock-pruned.yaml | head -1
      grep 'axios:' pnpm-lock-pruned.yaml
      ```

4. **Update Hash:**
    - Set `pnpmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="` as a placeholder in `flake.nix`.
    - Run `nix build .#openclaw-gateway.pnpmDeps 2>&1 | grep 'got:'`
    - Update `pnpmDepsHash` with the captured SRI hash.

5. **Verify:**
    - `nix build .#openclaw-gateway`
    - `nix run .#openclaw-gateway -- --version`

6. **Commit:** Commit `flake.nix`, `flake.lock`, and `pnpm-lock-pruned.yaml` together.

### Principles

- **No Manual Forcing:** Never manually edit `flake.lock` without a corresponding `flake.nix` URL change. Always update `flake.nix` first.
- **Use the Same Source:** The pruner MUST operate on the tarball from the commit in `flake.lock`. Do not download a separate tarball from a different URL/tag. The flake resolves the authoritative pin — the pruner uses that same resolution.
- **Verification First:** If a build fails with `ERR_PNPM_LOCKFILE_CONFIG_MISMATCH`, the `pnpm.overrides` block in the lockfile likely needs re-generation from the new upstream source. Re-prune before investigating Nix build logic.
- **Always Verify Hashes:** A passing build proves code works, but mismatched hashes prove nothing. Always verify `flake.nix` and `flake.lock` are in sync before building.
- **Never Commit Untracked Files:** `pnpm-lock.yaml` (the raw copy before pruning) should never be committed. Only `pnpm-lock-pruned.yaml` belongs in the repo.

## Project Structure Overview

| Artifact | Location | Format |
|----------|----------|--------|
| OpenClaw source pin | `flake.nix` → `inputs.openclaw.url` | GitHub ref (authoritative) |
| Resolved source | `flake.lock` → `inputs.openclaw.locked` | GitHub rev + narHash |
| Pruned lockfile | `pnpm-lock-pruned.yaml` | pnpm lockfile v9 (pruned) |
| pnpm deps hash | `flake.nix` → `pnpmDepsHash` | Nix hash (sha256-...) |
| Nixpkgs | `flake.lock` → `inputs.nixpkgs` | GitHub rev + narHash |
