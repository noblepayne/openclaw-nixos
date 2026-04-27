# Architecture

## Overview

`openclaw-nixos` is a minimal Nix flake that packages the [OpenClaw](https://github.com/openclaw/openclaw) gateway for NixOS servers. It is a fork of [nix-openclaw](https://github.com/nix-openclaw/nix-openclaw), stripped from ~18,700 lines to ~700.

**What it provides:**
- `packages.x86_64-linux.openclaw-gateway` — the built gateway binary
- `lib` — shared config/state rendering helpers
- `nixosModules.systemService` — a system-level NixOS module (`services.openclaw`)
- `nixosModules.userService` — a user-service NixOS module (`services.openclawUser`)
- `nixosModules.default` — alias of `systemService`
- `overlays.default` — an overlay providing `pkgs.openclaw` and `pkgs.openclaw-gateway`

**What it doesn't do:**
- No home-manager integration
- No macOS support
- No plugin catalog system
- No auto-generated 15k-line config schema

## Build pipeline

```
┌─────────────────────────┐
│  openclaw flake input   │  ← GitHub source, pinned in flake.lock
│  (git archive)          │
└───────────┬─────────────┘
            │
┌───────────▼─────────────┐
│  pnpm-lock-pruned.yaml  │  ← Our pruned lockfile (in repo)
│  (199 packages removed) │
└───────────┬─────────────┘
            │
┌───────────▼─────────────┐
│  fetchPnpmDeps          │  ← Downloads ~1,157 tarballs (not ~1,356)
│  (Nix store)            │
└───────────┬─────────────┘
            │
┌───────────▼─────────────┐
│  pnpm install           │  ← --offline --frozen-lockfile
│  (node_modules)         │
└───────────┬─────────────┘
            │
┌───────────▼─────────────┐
│  pnpm rebuild           │  ← Only native deps (sharp, canvas, etc.)
│  (native modules)       │
└───────────┬─────────────┘
            │
┌───────────▼─────────────┐
│  pnpm build             │  ← TypeScript → dist/
│  (dist/)                │
└───────────┬─────────────┘
            │
┌───────────▼─────────────┐
│  installPhase           │  ← $out/lib/openclaw/{dist,node_modules}
│  makeWrapper            │  ← $out/bin/openclaw
└─────────────────────────┘
```

## Runtime services

The NixOS module creates two services:

1. **`openclaw-setup.service`** (oneshot, runs as root)
   - Copies bundled extensions from the Nix store to `/var/lib/openclaw/dist/`
   - Symlinks `node_modules` from the store into the mutable `dist/`
   - Writes merged config to `/var/lib/openclaw/openclaw.json`
   - Writes cron jobs to `/var/lib/openclaw/cron/jobs.json`
   - Chowns the state directory to the service user

2. **`openclaw.service`** (the gateway process)
   - Runs as the `openclaw` user (with `bash` shell for exec/repl support)
   - Hardened: `NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome=true`

## Lockfile pruning

The upstream `pnpm-lock.yaml` includes platform-specific binaries for every OS and architecture (win32, darwin, android, wasm, mac, etc.). Since we only target linux x86_64, we strip ~200 unnecessary packages.

The pruner (`_tools/lockfile-pruner/prune.mjs`) uses `@pnpm/lockfile-file` to parse and write the lockfile — it never breaks pnpm's format. See `docs/lockfile-pruner.md` for details.

## Relationship to upstream

- **nix-openclaw**: The original Nix packaging (Unlicense). We copied and adapted their build scripts.
- **openclaw**: The upstream application. We pull source from their GitHub repo.
- **lattice**: Production instance that consumes and validates this module. Its config served as the template for the module's design.
