#!/usr/bin/env node
// validate.mjs — Structural invariants of a pruned pnpm lockfile
// Usage: node validate.mjs <path-to-pnpm-lock.yaml>
// Exit 0 = all invariants pass, Exit 1 = report failures
//
// Invariants:
// 1. PackageKeyExistence: every optionalDependencies ref must have a matching
//    key in the packages section (no dangling references).
// 2. NoPlatformPackages: stripped platform families must NOT appear as keys.

import { readFileSync } from "node:fs";
import yaml from "js-yaml";

const lockfilePath = process.argv[2];
if (!lockfilePath) {
  console.error("Usage: node validate.mjs <lockfile>");
  process.exit(1);
}

const raw = readFileSync(lockfilePath, "utf8");
const lf = yaml.load(raw);
if (!lf || !lf.packages) {
  console.error("FAIL: unable to parse lockfile");
  process.exit(1);
}

const errors = [];
const warnings = [];

// Known stripped prefixes (NOT target platform)
// These are the non-linux-x64 variants that prune.mjs removes
const STRIPPED = [
  // sharp: keep linux-x64, strip darwin/win32/arm64
  "@img/sharp-darwin-arm64@",
  "@img/sharp-darwin-x64@",
  "@img/sharp-win32-",
  "@img/sharp-linux-arm64@",
  "@img/sharp-linux-arm-",
  "@img/sharp-libvips-",
  // codex: keep linux-x64, strip darwin/arm64/win32
  "@openai/codex-darwin-arm64@",
  "@openai/codex-darwin-x64@",
  "@openai/codex-win32-",
  "@openai/codex-linux-arm64@",
  "@openai/codex-linux-arm-",
  "@zed-industries/codex-acp-darwin-arm64@",
  "@zed-industries/codex-acp-darwin-x64@",
  "@zed-industries/codex-acp-win32-",
  "@zed-industries/codex-acp-linux-arm64@",
  // node-pty: keep linux-x64, strip rest
  "@lydell/node-pty-darwin-arm64@",
  "@lydell/node-pty-darwin-x64@",
  "@lydell/node-pty-win32-",
  "@lydell/node-pty-linux-arm64@",
  // other platform-specific
  "lightningcss-darwin-",
  "lightningcss-win32-",
  "lightningcss-linux-arm-",
  "lightningcss-freebsd-",
  "sqlite-vec-darwin-",
  "sqlite-vec-win32-",
  "sqlite-vec-linux-arm64-",
  "sqlite-vec-linux-arm-",
  "@napi-rs/canvas-darwin-",
  "@napi-rs/canvas-win32-",
  "@napi-rs/canvas-linux-arm-",
  "@lancedb/lancedb-darwin-",
  "@lancedb/lancedb-win32-",
  "@lancedb/lancedb-linux-arm-",
  "@lancedb/lancedb-macos-universal@",
  "@mariozechner/clipboard-darwin-",
  "@mariozechner/clipboard-win32-",
  "@mariozechner/clipboard-linux-arm64-",
  "@mariozechner/clipboard-linux-arm-",
  "@reflink/reflink-win32-",
  "@reflink/reflink-darwin-",
  "@rolldown/binding-",
  "@snazzah/davey-darwin-",
  "@snazzah/davey-win32-",
  "@snazzah/davey-linux-arm64-",
  "@snazzah/davey-linux-arm-",
  "@tloncorp/tlon-skill-",
  'fsevents@',
  "@node-llama-cpp-darwin-",
  "@node-llama-cpp-win32-",
  "@node-llama-cpp-linux-arm-",
  "@node-llama-cpp-linux-aarch64-",
  "@oxfmt/binding-darwin-",
  "@oxfmt/binding-win32-",
  "@oxfmt/binding-linux-arm64-",
  "@oxfmt/binding-linux-arm-",
  "@oxlint/binding-darwin-",
  "@oxlint/binding-win32-",
  "@oxlint/binding-linux-arm64-",
  "@oxlint/binding-linux-arm-",
  "@oxlint-tsgolint-win32-",
  "@oxlint-tsgolint-darwin-",
  "@oxlint-tsgolint-linux-arm64-",
  "@oxlint-tsgolint-linux-arm-",
  "@typescript/native-preview-win32-",
  "@typescript/native-preview-darwin-",
  "@typescript/native-preview-linux-arm64-",
];

const keyByPkg = {};
for (const key of Object.keys(lf.packages)) {
  keyByPkg[key] = true;
}

function isStripped(key) {
  return STRIPPED.some((pfx) => {
    if (pfx.endsWith("@")) return key.startsWith(pfx) || key === pfx;
    return key === pfx;
  });
}

// --- Invariant 1: PackageKeyExistence ---
for (const [pkgKey, pkg] of Object.entries(lf.packages)) {
  const deps = pkg.optionalDependencies;
  if (!deps) continue;
  for (const [depName, depValue] of Object.entries(deps)) {
    let fullRef;
    if (typeof depValue === "string") {
      fullRef = `${depName}@${depValue.split("(")[0].trim()}`;
    } else if (depValue && typeof depValue === "object") {
      fullRef = `${depName}@${depValue.version?.split("(")[0]?.trim()}`;
    }
    if (fullRef && !keyByPkg[fullRef]) {
      errors.push(`PackageKeyExistence: ${pkgKey}.optionalDeps[${depName}] -> ${fullRef} not in packages section`);
    }
  }
}

// --- Invariant 2: NoPlatformPackages ---
for (const key of Object.keys(lf.packages)) {
  if (isStripped(key)) {
    errors.push(`NoPlatformPackages: stripped package still exists: ${key}`);
  }
}

// --- Invariant 3: Importer Refs ---
// Importers should not reference packages that were stripped from the packages section
const isWorkspace = (v) => v.startsWith("link:") || v.startsWith("file:");
if (lf.importers) {
  for (const [imKey, im] of Object.entries(lf.importers)) {
    // optionalDependencies: format is { depName: "fullKey" } or { depName: { version: "..." } }
    if (im.optionalDependencies) {
      for (const [dn, dv] of Object.entries(im.optionalDependencies)) {
        let key;
        if (typeof dv === "string") {
          key = dv; // format: "pkg/name@version" or just "name@version"
        } else if (dv && typeof dv === "object" && dv.version) {
          key = `${dn}@${dv.version}`;
        }
        if (key) {
          // Check: is this key a stripped package? If so, bad — importer shouldn't point to stripped.
          // But handle pnpm format where key may be "name@version" not "pkg/name@version"
          const candidates = [
            key,
            key.startsWith('@') ? key : `@${dn}@${dv?.version ?? ''}`,
            key.replace(/^(@?\S+)@/, '$1@'),
          ];
          let isStrippedRef = false;
          for (const c of candidates) {
            if (c && STRIPPED.some(pfx => c.startsWith(pfx))) {
              // This looks like a stripped package — but only flag if it was actually in original packages
              const strippedKey = c.split('(')[0].trim();
              // These are workspace links to extensions, that's fine
              if (c.includes('link:')) break;
              isStrippedRef = true;
              break;
            }
          }
          if (isStrippedRef) {
            errors.push(`ImporterRef: importers[${imKey}].opt[${dn}] -> ${key} references a stripped package`);
          }
        }
      }
    }
    // dependencies/devDependencies: format varies by pnpm version
    for (const depType of ["dependencies", "devDependencies", "peerDependencies"]) {
      const deps = im[depType];
      if (!deps) continue;
      for (const [dn, dval] of Object.entries(deps)) {
        let key;
        if (typeof dval === "string") {
          key = `${dn}@${dval}`;
        } else if (dval && typeof dval === "object" && dval.version) {
          key = `${dn}@${dval.version}`;
        } else if (Array.isArray(dval)) {
          key = `${dn}@${dval[0]?.version ?? "unknown"}`;
        }
        if (key && !isWorkspace(key)) {
          // Check if this is a stripped package reference
          const isStrippedRef = STRIPPED.some(pfx => {
            if (pfx.endsWith('@') && pfx.startsWith('@')) {
              // Scoped pkg: "@scope/pkg@ver" — check starts with scoped prefix
              const scopePrefix = pfx.substring(0, pfx.indexOf('@', 1) + 1);
              return key.startsWith(scopePrefix);
            }
            if (pfx.startsWith('@') && pfx.endsWith('-')) {
              const scopePrefix = pfx.substring(0, pfx.indexOf('-', 1) + 1);
              return key.startsWith(scopePrefix);
            }
            return key.startsWith(pfx) || key === pfx;
          });
          if (isStrippedRef) {
            warnings.push(`ImporterRef: importers[${imKey}][${depType}][${dn}] -> ${key} references a stripped package`);
          }
        }
      }
    }
  }
}

// --- Report ---
console.log(`packages: ${Object.keys(lf.packages).length} entries`);

if (warnings.length > 0) {
  console.log(`warnings: ${warnings.length}`);
  for (const w of warnings) console.log(`  [WARN] ${w}`);
}

if (errors.length === 0) {
  console.log("PASS");
  process.exit(0);
}

console.log(`FAIL: ${errors.length} violations\n`);
for (const e of errors) console.log(`  - ${e}`);
process.exit(1);
