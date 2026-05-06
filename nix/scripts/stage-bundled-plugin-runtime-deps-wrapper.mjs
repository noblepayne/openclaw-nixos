import path from "node:path";
import { pathToFileURL } from "node:url";

const upstreamModuleUrl = pathToFileURL(
  path.resolve(process.cwd(), "scripts/stage-bundled-plugin-runtime.mjs"),
).href;

const { stageBundledPluginRuntime } = await import(upstreamModuleUrl);

stageBundledPluginRuntime();
