{
  lib,
  stdenvNoCC,
  jq,
  pluginId,
  src,
  version ? "0.0.0",
  runtimeDepsPackage ? null,
}: let
  srcPath = toString src;
  manifestJsonPath = "${srcPath}/openclaw.plugin.json";
  packageJsonPath = "${srcPath}/package.json";
  manifestJson =
    if builtins.pathExists manifestJsonPath
    then builtins.fromJSON (builtins.readFile manifestJsonPath)
    else {};
  packageManifest =
    if builtins.pathExists packageJsonPath
    then builtins.fromJSON (builtins.readFile packageJsonPath)
    else {};
  hasDeclaredRuntimeDeps = (packageManifest.dependencies or {}) != {};
  runtimeDepsMetadata =
    if runtimeDepsPackage != null
    then runtimeDepsPackage.passthru.openclaw or {}
    else {};
  hasVendoredRuntimeDeps = runtimeDepsPackage != null;
  runtimeDepsStrategy =
    if hasVendoredRuntimeDeps
    then runtimeDepsMetadata.runtimeDepsStrategy or "external-package"
    else "none";
  validateManifest = ''
    if [ ! -f openclaw.plugin.json ]; then
      echo "missing openclaw.plugin.json in plugin source" >&2
      exit 1
    fi

    if [ ! -f package.json ]; then
      echo "missing package.json in plugin source" >&2
      exit 1
    fi

    manifest_id="$(${jq}/bin/jq -r '.id // empty' openclaw.plugin.json)"
    if [ "$manifest_id" != "${pluginId}" ]; then
      echo "pluginId ${pluginId} does not match openclaw.plugin.json id: $manifest_id" >&2
      exit 1
    fi
  '';
in
  assert lib.assertMsg (builtins.pathExists manifestJsonPath) "missing openclaw.plugin.json in plugin source for ${pluginId}";
  assert lib.assertMsg (builtins.pathExists packageJsonPath) "missing package.json in plugin source for ${pluginId}";
  assert lib.assertMsg ((manifestJson.id or null) == pluginId) "pluginId ${pluginId} does not match openclaw.plugin.json id: ${manifestJson.id or "<missing>"}";
  assert lib.assertMsg (!(hasDeclaredRuntimeDeps && !hasVendoredRuntimeDeps)) ''
    openclaw plugin ${pluginId} declares runtime dependencies in package.json, but no vendored runtimeDepsPackage was provided.
    Build a runtime deps package first with openclaw-nixos.lib.mkPluginRuntimeDepsFromNpmLock and pass it as runtimeDepsPackage,
    or use openclaw-nixos.lib.mkPluginPackage { runtimeDeps.npm = { npmDepsHash = "..."; ... }; }.
  '';
  assert lib.assertMsg (
    runtimeDepsPackage
    == null
    || (runtimeDepsMetadata.pluginId or pluginId) == pluginId
  ) "runtimeDepsPackage for ${pluginId} has mismatched passthru.openclaw.pluginId";
    stdenvNoCC.mkDerivation {
      pname = "openclaw-plugin-${pluginId}";
      inherit
        src
        version
        ;

      dontConfigure = true;
      dontBuild = true;

      installPhase = ''
        ${validateManifest}

        mkdir -p "$out"
        cp -r ./. "$out/"
        rm -rf "$out/.git" "$out/.github"

        ${lib.optionalString (runtimeDepsPackage != null) ''
          if [ ! -d ${runtimeDepsPackage}/node_modules ]; then
            echo "runtimeDepsPackage for ${pluginId} is missing node_modules" >&2
            exit 1
          fi

          tmp_package_json="$(mktemp)"
          ${jq}/bin/jq 'del(.dependencies, .devDependencies)' package.json > "$tmp_package_json"
          mv "$tmp_package_json" "$out/package.json"
          rm -f "$out/package-lock.json" "$out/npm-shrinkwrap.json"

          mkdir -p "$out/node_modules"
          cp -r ${runtimeDepsPackage}/node_modules/. "$out/node_modules/"
        ''}

        find "$out" -type d -exec chmod 0755 {} +
      '';

      passthru.openclaw = {
        inherit pluginId runtimeDepsStrategy;
        requiresRuntimeDeps = hasDeclaredRuntimeDeps;
        inherit hasVendoredRuntimeDeps;
      };

      meta = with lib; {
        description = "Packaged OpenClaw local plugin ${pluginId}";
        platforms = platforms.linux;
      };
    }
