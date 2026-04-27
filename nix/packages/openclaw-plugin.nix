{
  lib,
  stdenvNoCC,
  jq,
  pluginId,
  src,
  version ? "0.0.0",
}:
stdenvNoCC.mkDerivation {
  pname = "openclaw-plugin-${pluginId}";
  inherit
    src
    version
    ;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
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

    mkdir -p "$out"
    cp -r ./. "$out/"
    rm -rf "$out/.git" "$out/.github"
    find "$out" -type d -exec chmod 0755 {} +
  '';

  passthru.openclaw = {
    inherit pluginId;
  };

  meta = with lib; {
    description = "Packaged OpenClaw local plugin ${pluginId}";
    platforms = platforms.linux;
  };
}
