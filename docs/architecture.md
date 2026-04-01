# Architecture

## Overview

`openclaw-nixos` is a minimal Nix flake that packages the [OpenClaw](https://github.com/openclaw/openclaw) gateway for NixOS servers. It is a fork of [nix-openclaw](https://github.com/nix-openclaw/nix-openclaw), stripped from 18,685 lines to ~1,100.

**What it provides:**
- `packages.x86_64-linux.openclaw-gateway` — the built gateway binary
- `nixosModules.default` — a NixOS module (`services.openclaw`)
- `overlays.default` — an overlay for nixpkgs

**What it doesn't do:**
- No home-manager integration
- No macOS support
- No plugin catalog system
- No auto-generated 15k-line config schema
- No hourly CI auto-updater

## Dependencies

```
flake.nix
├── inputs.nixpkgs (NixOS/nixpkgs, nixos-unstable)
├── inputs.openclaw (openclaw/openclaw, main branch)
│   └── flake = false (source only, no flake outputs)
└── outputs
    ├── packages.x86_64-linux.openclaw-gateway
    │   └── nix/packages/openclaw-gateway.nix
    │       └── nix/lib/gateway-build.nix
    ├── nixosModules.default
    │   └── nix/modules/openclaw.nix
    └── overlays.default
```

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
│  fetchPnpmDeps          │  ← Downloads 1,157 tarballs (not 1,356)
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

## Lockfile pruning

The upstream `pnpm-lock.yaml` includes platform-specific binaries for every OS and architecture (win32, darwin, android, wasm, mac, etc.). Since we only target linux x86_64, we strip 199 unnecessary packages.

The pruner (`_tools/lockfile-pruner/prune.mjs`) uses `@pnpm/lockfile-file` to parse and write the lockfile — it never breaks pnpm's format. See `docs/lockfile-pruner.md` for details.

## Relationship to upstream

- **nix-openclaw**: The original Nix packaging (Unlicense). We copied and adapted their build scripts.
- **openclaw**: The upstream application. We pull source from their GitHub repo.
- **lattice**: Proof of concept that this simplified approach works. Their `openclaw.nix` was the template for our module.
