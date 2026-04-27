import path from "node:path";
import fs from "node:fs";
import { pathToFileURL } from "node:url";

const upstreamModuleUrl = pathToFileURL(
  path.resolve(process.cwd(), "scripts/stage-bundled-plugin-runtime-deps.mjs"),
).href;

const { stageBundledPluginRuntimeDeps } = await import(upstreamModuleUrl);
const stagingStrategy = process.env.OPENCLAW_NIX_STAGE_RUNTIME_DEPS_STRATEGY ?? "explicit";

function disablePluginRuntimeDepsStaging(pluginId) {
  const packageJsonPath = path.resolve(process.cwd(), "dist", "extensions", pluginId, "package.json");
  if (!fs.existsSync(packageJsonPath)) {
    return;
  }
  const parsed = JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));
  const bundle = {
    ...((parsed.openclaw && typeof parsed.openclaw === "object" ? parsed.openclaw.bundle : null) ?? {}),
    stageRuntimeDependencies: false,
  };
  parsed.openclaw = {
    ...(parsed.openclaw && typeof parsed.openclaw === "object" ? parsed.openclaw : {}),
    bundle,
  };
  fs.writeFileSync(packageJsonPath, `${JSON.stringify(parsed, null, 2)}\n`, "utf8");
}

const stagePluginIds = (process.env.OPENCLAW_NIX_STAGE_RUNTIME_DEPS_PLUGIN_IDS ?? "")
  .split(",")
  .map((entry) => entry.trim())
  .filter((entry) => entry.length > 0);

const stagePluginIdSet = new Set(stagePluginIds);
const extensionsDir = path.resolve(process.cwd(), "dist", "extensions");

if (fs.existsSync(extensionsDir)) {
  const availablePluginIds = fs
    .readdirSync(extensionsDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name);
  if (stagingStrategy === "explicit") {
    const availablePluginIdSet = new Set(availablePluginIds);
    const unknownPluginIds = stagePluginIds.filter((pluginId) => !availablePluginIdSet.has(pluginId));

    if (unknownPluginIds.length > 0) {
      throw new Error(
        `unknown bundled plugin IDs requested for staged runtime deps: ${unknownPluginIds.join(", ")}`,
      );
    }

    // Default to disabling runtime-deps staging for packaged bundled plugins,
    // then opt specific plugin IDs back in through the package override.
    for (const pluginId of availablePluginIds) {
      if (!stagePluginIdSet.has(pluginId)) {
        disablePluginRuntimeDepsStaging(pluginId);
      }
    }
  } else if (stagingStrategy !== "preserve") {
    throw new Error(`unknown OPENCLAW_NIX_STAGE_RUNTIME_DEPS_STRATEGY: ${stagingStrategy}`);
  }
}

stageBundledPluginRuntimeDeps({
  installPluginRuntimeDepsImpl(params) {
    const requestedSpecs = params.installSpecs ?? params.missingSpecs ?? [];
    throw new Error(
      "npm fallback disabled during Nix build for bundled plugin runtime deps" +
        (requestedSpecs.length > 0 ? `: ${requestedSpecs.join(", ")}` : ""),
    );
  },
});
