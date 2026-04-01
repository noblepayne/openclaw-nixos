#!/usr/bin/env node
// prune.mjs — Strip non-target platform binaries from a pnpm lockfile.
// Uses pnpm's own lockfile parser/writer so the format stays valid.
//
// Usage: node prune.mjs <lockfile-dir> [output-dir]
//   lockfile-dir: directory containing pnpm-lock.yaml
//   output-dir:   where to write the pruned lockfile (default: same dir)
//
// Environment:
//   TARGET_OS=linux   TARGET_CPU=x64   TARGET_LIBC=glibc
//   VERBOSE=1

import { readWantedLockfile, writeWantedLockfile } from "@pnpm/lockfile-file";
import { statSync, mkdirSync } from "node:fs";
import { resolve } from "node:path";

const lockfileDir = process.argv[2];
const outputDir = process.argv[3] || lockfileDir;
const verbose = process.env.VERBOSE === "1";

if (!lockfileDir) {
  console.error("Usage: node prune.mjs <lockfile-dir> [output-dir]");
  process.exit(1);
}

const lockfile = await readWantedLockfile(resolve(lockfileDir), {
  ignoreIncompatible: false,
});
if (!lockfile) {
  console.error("No lockfile found");
  process.exit(1);
}

// --- Platform families: prefix → keep(name) predicate ---
// Add new platform-specific package families here.
const FAMILIES = [
  { p: "@img/sharp-", k: (n) => /sharp-linux-x64@/.test(n) || /sharp-libvips-linux-x64@/.test(n) },
  { p: "@napi-rs/canvas-", k: (n) => /canvas-linux-x64-gnu@/.test(n) },
  { p: "@node-llama-cpp/", k: (n) => /llama-cpp\/linux-x64@/.test(n) },
  { p: "@esbuild/", k: (n) => /esbuild\/linux-x64@/.test(n) },
  { p: "@oxfmt/binding-", k: (n) => /oxfmt\/binding-linux-x64-gnu@/.test(n) },
  { p: "@oxlint/binding-", k: (n) => /oxlint\/binding-linux-x64-gnu@/.test(n) },
  { p: "@oxlint-tsgolint/", k: (n) => /tsgolint\/linux-x64/.test(n) },
  { p: "@lancedb/lancedb-", k: (n) => /lancedb-linux-x64-gnu@/.test(n) },
  { p: "@mariozechner/clipboard-", k: (n) => /clipboard-linux-x64-gnu@/.test(n) },
  { p: "@reflink/reflink-", k: (n) => /reflink-linux-x64-gnu@/.test(n) },
  { p: "@rolldown/binding-", k: (n) => /rolldown\/binding-linux-x64-gnu@/.test(n) },
  { p: "@snazzah/davey-", k: (n) => /davey-linux-x64-gnu@/.test(n) },
  { p: "@tloncorp/tlon-skill-", k: (n) => /tlon-skill-linux-x64/.test(n) },
  { p: "@typescript/native-preview-", k: (n) => /native-preview-linux-x64/.test(n) },
  { p: "@lydell/node-pty-", k: (n) => /node-pty-linux-x64/.test(n) },
  { p: "lightningcss-", k: (n) => /lightningcss-linux-x64-gnu/.test(n) },
  { p: "sqlite-vec-", k: (n) => /sqlite-vec-linux-x64/.test(n) },
  { p: "fsevents@", k: () => false }, // always strip (macOS only)
];

function isPlatformPkg(name) {
  return FAMILIES.some((f) => name.startsWith(f.p));
}
function shouldKeep(name) {
  for (const f of FAMILIES) if (name.startsWith(f.p)) return f.k(name);
  return true;
}

// Also catch any platform pkg by os/cpu metadata we didn't list above
function shouldStripByMeta(pkg) {
  if (!pkg?.os && !pkg?.cpu) return false;
  if (pkg.os?.length === 1 && pkg.os[0] !== "linux") return true;
  if (pkg.os?.length > 1 && !pkg.os.includes("linux")) return true;
  if (pkg.cpu?.length === 1 && pkg.cpu[0] !== "x64") return true;
  if (pkg.libc?.length === 1 && pkg.libc[0] === "musl") return true;
  return false;
}

// --- Phase 1: strip platform packages ---

const stripped = new Set();
if (lockfile.packages) {
  for (const [key, pkg] of Object.entries(lockfile.packages)) {
    let drop = false;
    if (isPlatformPkg(key)) drop = !shouldKeep(key);
    else if (shouldStripByMeta(pkg)) drop = true;
    if (drop) {
      stripped.add(key);
      if (verbose) console.error(`  [pkg] ${key}`);
      delete lockfile.packages[key];
    }
  }
}

// --- Phase 2: clean dangling refs in remaining packages ---
// In pnpm v9, snapshots are merged into packages. optionalDependencies
// and other dep lists live directly on the package entry object.
// Stripped keys may include peer dep suffixes like "pkg@1.0.0(peer@2.0.0)"
// while refs are just "pkg: 1.0.0", so we need prefix matching.

// Build a fast lookup: "name@version" → is stripped
const strippedPrefixes = new Map();
for (const k of stripped) {
  const base = k.split("(")[0];
  if (!strippedPrefixes.has(base)) strippedPrefixes.set(base, []);
  strippedPrefixes.get(base).push(k);
}

if (lockfile.packages) {
  let cleanedRefs = 0;
  for (const [key, pkg] of Object.entries(lockfile.packages)) {
    for (const depType of [
      "dependencies",
      "optionalDependencies",
      "peerDependencies",
    ]) {
      if (!pkg[depType]) continue;
      for (const depName of Object.keys(pkg[depType])) {
        const ver = pkg[depType][depName];
        const baseVer = typeof ver === "string" ? ver.split("(")[0] : ver;
        const prefix = `${depName}@${baseVer}`;
        if (strippedPrefixes.has(prefix)) {
          if (verbose)
            console.error(`    [${key}] ${depType}.${depName}@${baseVer}`);
          delete pkg[depType][depName];
          cleanedRefs++;
        }
      }
      if (Object.keys(pkg[depType]).length === 0) delete pkg[depType];
    }
  }
  console.error(`Cleaned ${cleanedRefs} dangling refs in package entries`);
}

// --- Write ---

if (outputDir !== lockfileDir) mkdirSync(outputDir, { recursive: true });
await writeWantedLockfile(resolve(outputDir), lockfile);

// --- Stats ---
const origSize = statSync(resolve(lockfileDir, "pnpm-lock.yaml")).size;
const newSize = statSync(resolve(outputDir, "pnpm-lock.yaml")).size;
const saved = origSize - newSize;
console.log(`\nStripped ${stripped.size} platform packages`);
console.log(
  `${(origSize / 1024).toFixed(0)} KB → ${(newSize / 1024).toFixed(0)} KB (saved ${(saved / 1024).toFixed(0)} KB, ${((saved / origSize) * 100).toFixed(1)}%)`,
);
console.log(`Written to: ${resolve(outputDir, "pnpm-lock.yaml")}`);
