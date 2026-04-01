# Nix Build

## Prerequisites

- Nix with flakes enabled (`experimental-features = nix-command flakes`)
- Linux x86_64

## Building

```bash
cd ~/src/openclaw-nixos
nix build .#openclaw-gateway
```

The result symlink points to `/nix/store/<hash>-openclaw-gateway/`.

## What happens during the build

### 1. fetchPnpmDeps

Reads `pnpm-lock-pruned.yaml`, resolves all 1,157 package tarballs, downloads them into a compressed Nix store path. This is the slowest step on first build (~2-5 min depending on connection). Cached after first run.

### 2. postPatch

- Copies our pruned lockfile over the upstream one (`cp ${prunedLockfile} pnpm-lock.yaml`)
- Runs `gateway-postpatch.sh` which patches:
  - `src/logging/logger.ts` — adds `OPENCLAW_LOG_DIR` env var support
  - `src/agents/shell-utils.ts` — handles missing SHELL in Nix sandbox
  - `src/docker-setup.test.ts` — bash → sh compatibility
  - `package.json` — removes `packageManager` field

### 3. buildPhase (gateway-build.sh)

1. Extract pnpm store from tar.zst
2. `promote-pnpm-integrity.sh` — marks non-build deps as built
3. `node-gyp wrapper` — wraps node-gyp for native module rebuilds
4. `pnpm install --offline --frozen-lockfile --ignore-scripts`
5. `pnpm rebuild` — rebuilds only `onlyBuiltDependencies` from package.json
6. `patchShebangs node_modules/.bin`
7. Build steps: `canvas:a2ui:bundle`, `tsdown`, `plugin-sdk:dts`, etc.
8. `pnpm ui:build` — builds the control UI (included in gateway package)
9. `pnpm prune --prod` — removes dev dependencies

### 4. installPhase (gateway-install.sh)

1. `mv dist node_modules package.json $out/lib/openclaw/`
2. Copy `extensions/` and `docs/reference/templates/` if present
3. Symlink workarounds for missing deps (`strip-ansi`, `combined-stream`, `hasown`)
4. Patch clipboard for headless Linux (`patch-clipboard.sh`)
5. `makeWrapper` — creates `$out/bin/openclaw` pointing to `dist/index.js`

## Key environment variables

| Variable | Purpose |
|----------|---------|
| `npm_config_arch` | Target architecture (x64) |
| `npm_config_platform` | Target platform (linux) |
| `SHARP_IGNORE_GLOBAL_LIBVIPS` | Don't use system vips for sharp |
| `NODE_LLAMA_CPP_SKIP_DOWNLOAD` | Don't download llama.cpp binaries |
| `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD` | Don't download browsers |
| `PNPM_DEPS` | Path to fetched pnpm store |

## Common issues

### Hash mismatch

If you see `error: hash mismatch`, copy the `got:` hash into `flake.nix` `pnpmDepsHash`.

### Build fails on a specific native module

Check the build log for the specific error. Common causes:
- Missing native library (add to `extraBuildInputs` in `gateway-build.nix`)
- Wrong architecture (check `npm_config_arch` / `npm_config_platform`)
- Network blocked in sandbox (should be handled by `--offline`)

### Lockfile mismatch

If `pnpm install --frozen-lockfile` fails, the pruned lockfile doesn't match the source. Regenerate it with the pruner.
