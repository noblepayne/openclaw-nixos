#!/bin/sh
set -e
if [ -f package.json ]; then
  "$REMOVE_PACKAGE_MANAGER_FIELD_SH" package.json
fi

if [ -f src/logging/logger.ts ]; then
  if ! grep -q "OPENCLAW_LOG_DIR" src/logging/logger.ts; then
    sed -i 's/export const DEFAULT_LOG_DIR = "\/tmp\/openclaw";/export const DEFAULT_LOG_DIR = process.env.OPENCLAW_LOG_DIR ?? "\/tmp\/openclaw";/' src/logging/logger.ts
  fi
fi

if [ -f src/agents/shell-utils.ts ]; then
  if ! grep -q "envShell" src/agents/shell-utils.ts; then
    awk '
      /import { spawn } from "node:child_process";/ {
        print;
        print "import { existsSync } from \"node:fs\";";
        next;
      }
      /const shell = process.env.SHELL/ {
        print "  const envShell = process.env.SHELL?.trim();";
        print "  const shell =";
        print "    envShell && envShell.startsWith(\"/\") && !existsSync(envShell)";
        print "      ? \"sh\"";
        print "      : envShell || \"sh\";";
        next;
      }
      { print }
    ' src/agents/shell-utils.ts > src/agents/shell-utils.ts.next
    mv src/agents/shell-utils.ts.next src/agents/shell-utils.ts
  fi
fi

if [ -f src/docker-setup.test.ts ]; then
  if ! grep -q "#!/bin/sh" src/docker-setup.test.ts; then
    sed -i 's|#!/usr/bin/env bash|#!/bin/sh|' src/docker-setup.test.ts
    sed -i 's/set -euo pipefail/set -eu/' src/docker-setup.test.ts
    sed -i 's|if \[\[ "${1:-}" == "compose" && "${2:-}" == "version" \]\]; then|if [ "${1:-}" = "compose" ] && [ "${2:-}" = "version" ]; then|' src/docker-setup.test.ts
    sed -i 's|if \[\[ "${1:-}" == "build" \]\]; then|if [ "${1:-}" = "build" ]; then|' src/docker-setup.test.ts
    sed -i 's|if \[\[ "${1:-}" == "compose" \]\]; then|if [ "${1:-}" = "compose" ]; then|' src/docker-setup.test.ts
  fi
fi

if [ -f src/plugins/bundled-runtime-deps.ts ]; then
  python3 <<'PY'
from pathlib import Path

path = Path("src/plugins/bundled-runtime-deps.ts")
text = path.read_text()

if "resolveExistingExternalBundledRuntimeDepsInstallRoot" not in text:
    old = """function resolveExternalBundledRuntimeDepsInstallRoot(params: {\n  pluginRoot: string;\n  env: NodeJS.ProcessEnv;\n}): string {\n  const packageRoot = resolveBundledPluginPackageRoot(params.pluginRoot) ?? params.pluginRoot;\n  const version = sanitizePathSegment(readPackageVersion(packageRoot));\n  const packageKey = `openclaw-${version}-${createPathHash(packageRoot)}`;\n  return path.join(resolveBundledRuntimeDepsExternalBaseDir(params.env), packageKey);\n}\n"""
    new = """function resolveExternalBundledRuntimeDepsInstallRoot(params: {\n  pluginRoot: string;\n  env: NodeJS.ProcessEnv;\n}): string {\n  const packageRoot = resolveBundledPluginPackageRoot(params.pluginRoot) ?? params.pluginRoot;\n  const version = sanitizePathSegment(readPackageVersion(packageRoot));\n  const packageKey = `openclaw-${version}-${createPathHash(packageRoot)}`;\n  return path.join(resolveBundledRuntimeDepsExternalBaseDir(params.env), packageKey);\n}\n\nfunction resolveExistingExternalBundledRuntimeDepsInstallRoot(params: {\n  pluginRoot: string;\n  env: NodeJS.ProcessEnv;\n}): string | null {\n  const packageRoot = resolveBundledPluginPackageRoot(params.pluginRoot);\n  if (!packageRoot) {\n    return null;\n  }\n  const externalBaseDir = path.resolve(resolveBundledRuntimeDepsExternalBaseDir(params.env));\n  const resolvedPackageRoot = path.resolve(packageRoot);\n  if (\n    resolvedPackageRoot === externalBaseDir ||\n    resolvedPackageRoot.startsWith(`${externalBaseDir}${path.sep}`)\n  ) {\n    return packageRoot;\n  }\n  return null;\n}\n"""
    if old not in text:
        raise SystemExit("failed to patch resolveExternalBundledRuntimeDepsInstallRoot")
    text = text.replace(old, new, 1)

package_old = """export function resolveBundledRuntimeDependencyPackageInstallRoot(\n  packageRoot: string,\n  options: { env?: NodeJS.ProcessEnv; forceExternal?: boolean } = {},\n): string {\n  const env = options.env ?? process.env;\n  if (\n    options.forceExternal ||\n    env.OPENCLAW_PLUGIN_STAGE_DIR?.trim() ||\n    env.STATE_DIRECTORY?.trim()\n  ) {\n    return resolveExternalBundledRuntimeDepsInstallRoot({\n      pluginRoot: path.join(packageRoot, \"dist\", \"extensions\", \"__package__\"),\n      env,\n    });\n  }\n"""
package_new = """export function resolveBundledRuntimeDependencyPackageInstallRoot(\n  packageRoot: string,\n  options: { env?: NodeJS.ProcessEnv; forceExternal?: boolean } = {},\n): string {\n  const env = options.env ?? process.env;\n  if (\n    options.forceExternal ||\n    env.OPENCLAW_PLUGIN_STAGE_DIR?.trim() ||\n    env.STATE_DIRECTORY?.trim()\n  ) {\n    const existingExternalRoot = resolveExistingExternalBundledRuntimeDepsInstallRoot({\n      pluginRoot: path.join(packageRoot, \"dist\", \"extensions\", \"__package__\"),\n      env,\n    });\n    if (existingExternalRoot) {\n      return existingExternalRoot;\n    }\n    return resolveExternalBundledRuntimeDepsInstallRoot({\n      pluginRoot: path.join(packageRoot, \"dist\", \"extensions\", \"__package__\"),\n      env,\n    });\n  }\n"""
if package_old in text and "const existingExternalRoot = resolveExistingExternalBundledRuntimeDepsInstallRoot({\n      pluginRoot: path.join(packageRoot, \"dist\", \"extensions\", \"__package__\")" not in text:
    text = text.replace(package_old, package_new, 1)

plugin_old = """export function resolveBundledRuntimeDependencyInstallRoot(\n  pluginRoot: string,\n  options: { env?: NodeJS.ProcessEnv; forceExternal?: boolean } = {},\n): string {\n  const env = options.env ?? process.env;\n  if (\n    options.forceExternal ||\n    env.OPENCLAW_PLUGIN_STAGE_DIR?.trim() ||\n    env.STATE_DIRECTORY?.trim()\n  ) {\n    return resolveExternalBundledRuntimeDepsInstallRoot({ pluginRoot, env });\n  }\n"""
plugin_new = """export function resolveBundledRuntimeDependencyInstallRoot(\n  pluginRoot: string,\n  options: { env?: NodeJS.ProcessEnv; forceExternal?: boolean } = {},\n): string {\n  const env = options.env ?? process.env;\n  if (\n    options.forceExternal ||\n    env.OPENCLAW_PLUGIN_STAGE_DIR?.trim() ||\n    env.STATE_DIRECTORY?.trim()\n  ) {\n    const existingExternalRoot = resolveExistingExternalBundledRuntimeDepsInstallRoot({ pluginRoot, env });\n    if (existingExternalRoot) {\n      return existingExternalRoot;\n    }\n    return resolveExternalBundledRuntimeDepsInstallRoot({ pluginRoot, env });\n  }\n"""
if plugin_old in text and "const existingExternalRoot = resolveExistingExternalBundledRuntimeDepsInstallRoot({ pluginRoot, env });" not in text:
    text = text.replace(plugin_old, plugin_new, 1)

path.write_text(text)
PY
fi

if [ -f src/plugins/loader.ts ]; then
  python3 <<'PY'
from pathlib import Path

path = Path("src/plugins/loader.ts")
text = path.read_text()

if "copyBundledPluginRuntimePackageMetadata" not in text:
    anchor = """function prepareBundledPluginRuntimeDistMirror(params: {\n  installRoot: string;\n  pluginRoot: string;\n}): string {\n"""
    helper = """function copyBundledPluginRuntimePackageMetadata(params: {\n  installRoot: string;\n  pluginRoot: string;\n}): void {\n  const packageRoot = path.dirname(path.dirname(path.dirname(path.resolve(params.pluginRoot))));\n  const sourcePackageJson = path.join(packageRoot, "package.json");\n  const targetPackageJson = path.join(params.installRoot, "package.json");\n  if (fs.existsSync(sourcePackageJson) && !fs.existsSync(targetPackageJson)) {\n    fs.copyFileSync(sourcePackageJson, targetPackageJson);\n  }\n}\n\n""" + anchor
    if anchor not in text:
        raise SystemExit("failed to locate prepareBundledPluginRuntimeDistMirror anchor")
    text = text.replace(anchor, helper, 1)

marker = """  const mirrorDistRoot = path.join(params.installRoot, sourceDistRootName);\n  const mirrorExtensionsRoot = path.join(mirrorDistRoot, "extensions");\n"""
replacement = """  const mirrorDistRoot = path.join(params.installRoot, sourceDistRootName);\n  const mirrorExtensionsRoot = path.join(mirrorDistRoot, "extensions");\n  copyBundledPluginRuntimePackageMetadata(params);\n"""
if marker in text and "copyBundledPluginRuntimePackageMetadata(params);" not in text:
    text = text.replace(marker, replacement, 1)

path.write_text(text)
PY
fi
