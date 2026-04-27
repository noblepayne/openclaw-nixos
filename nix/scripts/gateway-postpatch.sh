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
  if ! grep -q "resolveExistingExternalBundledRuntimeDepsInstallRoot" src/plugins/bundled-runtime-deps.ts; then
    perl -0pi -e 's@function resolveExternalBundledRuntimeDepsInstallRoot\(params: \{\n  pluginRoot: string;\n  env: NodeJS\.ProcessEnv;\n\}\): string \{\n  const packageRoot = resolveBundledPluginPackageRoot\(params\.pluginRoot\) \?\? params\.pluginRoot;\n  const version = sanitizePathSegment\(readPackageVersion\(packageRoot\)\);\n  const packageKey = `openclaw-\$\{version\}-\$\{createPathHash\(packageRoot\)\}`;\n  return path\.join\(resolveBundledRuntimeDepsExternalBaseDir\(params\.env\), packageKey\);\n\}\n@function resolveExternalBundledRuntimeDepsInstallRoot(params: {\n  pluginRoot: string;\n  env: NodeJS.ProcessEnv;\n}): string {\n  const packageRoot = resolveBundledPluginPackageRoot(params.pluginRoot) ?? params.pluginRoot;\n  const version = sanitizePathSegment(readPackageVersion(packageRoot));\n  const packageKey = "openclaw-" + version + "-" + createPathHash(packageRoot);\n  return path.join(resolveBundledRuntimeDepsExternalBaseDir(params.env), packageKey);\n}\n\nfunction resolveExistingExternalBundledRuntimeDepsInstallRoot(params: {\n  pluginRoot: string;\n  env: NodeJS.ProcessEnv;\n}): string | null {\n  const packageRoot = resolveBundledPluginPackageRoot(params.pluginRoot);\n  if (!packageRoot) {\n    return null;\n  }\n  const externalBaseDir = path.resolve(resolveBundledRuntimeDepsExternalBaseDir(params.env));\n  const resolvedPackageRoot = path.resolve(packageRoot);\n  if (\n    resolvedPackageRoot === externalBaseDir ||\n    resolvedPackageRoot.startsWith(externalBaseDir + path.sep)\n  ) {\n    return packageRoot;\n  }\n  return null;\n}\n@' src/plugins/bundled-runtime-deps.ts

    perl -0pi -e 's@const env = options\.env \?\? process\.env;\n  const externalRoot = resolveExternalBundledRuntimeDepsInstallRoot\(\{\n@const env = options.env ?? process.env;\n  const existingExternalRoot = resolveExistingExternalBundledRuntimeDepsInstallRoot({\n    pluginRoot: path.join(packageRoot, "dist", "extensions", "__package__"),\n    env,\n  });\n  if (existingExternalRoot) {\n    return existingExternalRoot;\n  }\n  const externalRoot = resolveExternalBundledRuntimeDepsInstallRoot({\n@' src/plugins/bundled-runtime-deps.ts

    perl -0pi -e 's@const env = options\.env \?\? process\.env;\n  const externalRoot = resolveExternalBundledRuntimeDepsInstallRoot\(\{ pluginRoot, env \}\);\n@const env = options.env ?? process.env;\n  const existingExternalRoot = resolveExistingExternalBundledRuntimeDepsInstallRoot({ pluginRoot, env });\n  if (existingExternalRoot) {\n    return existingExternalRoot;\n  }\n  const externalRoot = resolveExternalBundledRuntimeDepsInstallRoot({ pluginRoot, env });\n@' src/plugins/bundled-runtime-deps.ts
  fi
fi
