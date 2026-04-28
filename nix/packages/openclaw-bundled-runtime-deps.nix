{
  lib,
  runCommand,
  jq,
  package,
  pluginIds ? [],
}: let
  normalizedPluginIds = lib.sort builtins.lessThan (lib.unique pluginIds);
  pluginIdsJson = builtins.toJSON normalizedPluginIds;
in
  runCommand "openclaw-bundled-runtime-deps-${package.version or "unknown"}" {
    nativeBuildInputs = [jq];
  } ''
    set -euo pipefail

    package_root="${package}/lib/openclaw"
    if [ ! -f "$package_root/package.json" ]; then
      package_root="${package}"
    fi
    extensions_dir="$package_root/dist/extensions"
    plugin_ids='${pluginIdsJson}'

    version="$(
      jq -r '.version // "unknown"' "$package_root/package.json" \
        | sed -E 's/[^A-Za-z0-9._-]+/-/g; s/^-+|-+$//g; s/^$/unknown/'
    )"
    package_hash="$(printf '%s' "$package_root" | sha256sum | cut -c1-12)"
    package_key="openclaw-$version-$package_hash"
    install_root="$out/$package_key"

    mkdir -p "$out"
    printf '%s\n' "$plugin_ids" > "$out/.openclaw-selected-plugin-ids.json"
    printf '%s\n' "$package_key" > "$out/.openclaw-package-key"

    runtime_dep_plugin_count=0
    while IFS= read -r plugin_id; do
      [ -n "$plugin_id" ] || continue
      if [ ! -d "$extensions_dir/$plugin_id" ]; then
        echo "unknown bundled plugin ID requested for runtime deps: $plugin_id" >&2
        exit 1
      fi
      if jq -e '((.dependencies // {}) + (.optionalDependencies // {})) | length > 0' \
        "$extensions_dir/$plugin_id/package.json" >/dev/null; then
        runtime_dep_plugin_count=$((runtime_dep_plugin_count + 1))
      fi
    done < <(jq -r '.[]' <<<"$plugin_ids")

    if [ "$runtime_dep_plugin_count" -eq 0 ]; then
      mkdir -p "$install_root"
      exit 0
    fi

    mkdir -p "$install_root"
    cp -a "$package_root/node_modules" "$install_root/node_modules"
    chmod -R u+w "$install_root" || true
  ''
