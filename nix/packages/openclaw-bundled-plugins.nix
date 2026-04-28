{
  lib,
  jq,
  runCommand,
  package,
  pluginIds ? [],
}: let
  normalizedPluginIds = lib.sort builtins.lessThan (lib.unique pluginIds);
  pluginIdsJson = builtins.toJSON normalizedPluginIds;
in
  runCommand "openclaw-bundled-plugins-${package.version or "unknown"}" {
    nativeBuildInputs = [jq];
  } ''
    set -euo pipefail

    package_root="${package}/lib/openclaw"
    extensions_dir="$package_root/dist/extensions"
    plugin_ids='${pluginIdsJson}'

    mkdir -p "$out"
    cp "$package_root/package.json" "$out/package.json"
    ln -s "$package_root/node_modules" "$out/node_modules"
    cp -r "$package_root/dist" "$out/dist"
    chmod -R u+w "$out/dist"
    rm -rf "$out/dist/extensions"
    mkdir -p "$out/dist/extensions"

    if [ -d "$extensions_dir/node_modules" ]; then
      cp -r "$extensions_dir/node_modules" "$out/dist/extensions/node_modules"
    fi

    while IFS= read -r plugin_id; do
      [ -n "$plugin_id" ] || continue
      if [ ! -d "$extensions_dir/$plugin_id" ]; then
        echo "unknown bundled plugin ID requested: $plugin_id" >&2
        exit 1
      fi
      cp -r "$extensions_dir/$plugin_id" "$out/dist/extensions/$plugin_id"
    done < <(jq -r '.[]' <<<"$plugin_ids")
  ''
