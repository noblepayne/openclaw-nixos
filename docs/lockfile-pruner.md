# Lockfile Pruner

## Purpose

The upstream OpenClaw `pnpm-lock.yaml` includes platform-specific binary packages for every OS and architecture. For a linux x86_64 server build, we don't need:

- Windows packages (sharp-win32, canvas-win32, esbuild-win32, llama.cpp-win, etc.)
- macOS packages (sharp-darwin, canvas-darwin, fsevents, llama.cpp-mac, etc.)
- Android packages (canvas-android, esbuild-android, etc.)
- Other architectures (arm64, arm, riscv64, ppc64, s390x, wasm32)
- musl variants (when targeting glibc)

The pruner removes **199 platform-specific packages** and their dangling references, saving ~68 KB of YAML and hundreds of MB of unnecessary downloads.

## Usage

```bash
cd ~/src/openclaw-nixos

# Prune from an openclaw checkout
node _tools/lockfile-pruner/prune.mjs /path/to/openclaw .

# The output is pnpm-lock.yaml in the current directory
mv pnpm-lock.yaml pnpm-lock-pruned.yaml
```

## How it works

Uses `@pnpm/lockfile-file` — pnpm's own lockfile parser/writer. This guarantees the output is a valid pnpm lockfile that `pnpm install --frozen-lockfile` accepts.

### Phase 1: Strip platform packages

Iterates over every package entry. For each known platform family (sharp, canvas, esbuild, llama.cpp, etc.), keeps only the linux x64 glibc variant. Also strips by `os`/`cpu` metadata as a fallback for unknown packages.

### Phase 2: Clean dangling references

Removes references to stripped packages from `optionalDependencies` of remaining packages. Uses prefix matching to handle peer dependency suffixes in package keys.

## Platform families

The pruner has a hardcoded list of platform families. When upstream adds new platform-specific packages, add them to the `FAMILIES` array in `prune.mjs`:

```javascript
{ p: "@new-package/platform-", k: (n) => /linux-x64-gnu/.test(n) },
```

Current families (19):
- `@img/sharp-*`
- `@napi-rs/canvas-*`
- `@node-llama-cpp/*`
- `@esbuild/*`
- `@oxfmt/binding-*`
- `@oxlint/binding-*`
- `@oxlint-tsgolint/*`
- `@lancedb/lancedb-*`
- `@mariozechner/clipboard-*`
- `@reflink/reflink-*`
- `@rolldown/binding-*`
- `@snazzah/davey-*`
- `@tloncorp/tlon-skill-*`
- `@typescript/native-preview-*`
- `@lydell/node-pty-*`
- `lightningcss-*`
- `sqlite-vec-*`
- `fsevents@` (always stripped — macOS only)

## Validation

The pruned lockfile was validated against upstream `openclaw@2026.3.31`:

| Test | Result |
|------|--------|
| `pnpm install --frozen-lockfile` | ✅ Pass (exit 0) |
| `pnpm build` | ✅ Pass (exit 0) |
| All postinstall scripts | ✅ Pass (sharp, esbuild, canvas, llama.cpp, etc.) |

## Adding new platform packages

When upstream adds a new native module with platform-specific binaries:

1. Add it to the `FAMILIES` array in `prune.mjs`
2. Regenerate the pruned lockfile
3. Verify with `pnpm install --frozen-lockfile`
4. Update `pnpmDepsHash` in `flake.nix`
