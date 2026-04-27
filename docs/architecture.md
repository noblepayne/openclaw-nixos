# Architecture

## Overview

`openclaw-nixos` is a composable Nix platform for the [OpenClaw](https://github.com/openclaw/openclaw) gateway. It packages upstream OpenClaw, exposes reusable Nix helpers, and ships both system-service and user-service adapters for downstream hosts.

**What it provides:**
- `packages.x86_64-linux.openclaw-gateway` — the built gateway binary
- `packages.x86_64-linux.openclaw-bundled-runtime-deps` — a package-scoped bundled runtime-deps artifact
- `lib` — shared config/state rendering helpers
- `lib.pluginProfiles` — reusable plugin baseline attrsets for downstream composition
- `nixosModules.systemService` — a system-level NixOS module (`services.openclaw`)
- `nixosModules.userService` — a user-service NixOS module (`services.openclawUser`)
- `nixosModules.profileChat`, `profileBrowserAutomation`, `profileAcp` — thin plugin-profile modules that can apply shared defaults to either adapter
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
│  selective bundled      │  ← filtered bundled-plugin artifact
│  plugin artifact        │
└───────────┬─────────────┘
            │
┌───────────▼─────────────┐
│  selective runtime deps │  ← package-scoped dep closure for chosen plugins
│  + stage artifact       │
└───────────┬─────────────┘
            │
┌───────────▼─────────────┐
│  installPhase           │  ← $out/lib/openclaw/{dist,node_modules}
│  makeWrapper            │  ← $out/bin/openclaw
└─────────────────────────┘
```

Bundled plugin preparation is now split across two artifacts:

- `openclaw-bundled-plugins` filters the bundled plugin tree to only the enabled plugin IDs
- `openclaw-bundled-runtime-deps` materializes the package-scoped runtime-deps closure consumed through `OPENCLAW_PLUGIN_STAGE_DIR`

The modules then assemble the live runtime root from those artifacts before startup. That keeps packaged deployments off the runtime `npm install` path while still matching upstream's external stage-root contract.

## Runtime services

The service adapters share the same package and rendering layer, but differ in ownership and activation style.

## Plugin profiles

Plugin ownership is meant to layer cleanly:

- upstream exposes the plugin interface and reusable profile fragments
- a shared downstream module can define a common baseline
- each host can add, disable, or override plugins declaratively

`openclaw-nixos` now exposes both:

- `lib.pluginProfiles.*` for plain attrset composition
- `nixosModules.profile*` for import-based profile layering

These profiles intentionally stay generic. They are not host policy and should not encode Nomad-specific local plugins or secrets.

### `systemService`

The system adapter creates:

1. **`openclaw-setup.service`** (oneshot, runs as root)
   - Creates the state root under `/var/lib/openclaw`
   - Writes merged config to `/var/lib/openclaw/openclaw.json`
   - Writes cron jobs to `/var/lib/openclaw/cron/jobs.json`
   - If `mutableExtensionsDir = true`, copies the packaged `dist/` tree into writable state and replaces `dist/extensions` with the selected bundled plugin set
   - If bundled runtime deps are configured, assembles `/var/lib/openclaw/plugin-runtime-deps/<package-key>/` from the selected bundled plugin tree plus the prebuilt dependency closure
   - Chowns the state directory to the service user

2. **`openclaw.service`** (the gateway process)
   - Runs as the `openclaw` user
   - Uses either the mutable bundled-plugin tree in state or the filtered read-only bundled-plugin artifact directly
   - Reads the assembled bundled runtime stage via `OPENCLAW_PLUGIN_STAGE_DIR`
   - Uses hardening such as `NoNewPrivileges`, `ProtectSystem=strict`, and `ProtectHome=true`

### `userService`

The user adapter:

- renders the same config and plugin model under `services.openclawUser`
- runs setup through a NixOS activation script instead of a root-owned oneshot service
- runs the gateway as a `systemd.user` unit
- defaults state under the target user's home directory
- supports the same filtered bundled-plugin and staged runtime-deps behavior as `systemService`

## Lockfile pruning

The upstream `pnpm-lock.yaml` includes platform-specific binaries for every OS and architecture (win32, darwin, android, wasm, mac, etc.). Since we only target linux x86_64, we strip ~200 unnecessary packages.

The pruner (`_tools/lockfile-pruner/prune.mjs`) uses `@pnpm/lockfile-file` to parse and write the lockfile — it never breaks pnpm's format. See `docs/lockfile-pruner.md` for details.

## Relationship to upstream

- **nix-openclaw**: The original Nix packaging (Unlicense). We copied and adapted their build scripts.
- **openclaw**: The upstream application. We pull source from their GitHub repo.
- **nomad**: A downstream user-service consumer that validates the shared package, plugin, and stage-root model against a real production-like host.
