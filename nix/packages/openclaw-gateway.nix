{
  lib,
  stdenv,
  fetchurl,
  nodejs_22,
  pnpm_10,
  fetchPnpmDeps,
  pkg-config,
  jq,
  python3,
  perl,
  node-gyp,
  makeWrapper,
  vips,
  git,
  zstd,
  runCommand,
  openclawSrc,
  prunedLockfile,
  pnpmDepsHash,
  stagedRuntimeDepsPluginIds ? [],
}: let
  normalizedStagedRuntimeDepsPluginIds =
    if stagedRuntimeDepsPluginIds == null
    then null
    else lib.sort builtins.lessThan (lib.unique stagedRuntimeDepsPluginIds);

  # OpenClaw source with our pruned lockfile substituted in.
  # This ensures fetchPnpmDeps reads the pruned lockfile (1,157 packages)
  # instead of the upstream one (1,356 packages with win32/darwin/android/wasm).
  # We normalize timestamps to ensure deterministic output.
  patchedSrc = runCommand "openclaw-source" {} ''
    cp -r --no-preserve=ownership,timestamps ${openclawSrc} $out
    chmod -R u+w $out
    cp ${prunedLockfile} $out/pnpm-lock.yaml
    # Normalize timestamps for deterministic output
    find $out -exec touch -t 198001010000 {} +
  '';

  common =
    import ../lib/gateway-build.nix
    {
      inherit
        lib
        stdenv
        fetchurl
        nodejs_22
        pnpm_10
        fetchPnpmDeps
        pkg-config
        jq
        python3
        node-gyp
        git
        zstd
        ;
    }
    {
      pname = "openclaw-gateway";
      src = patchedSrc;
      inherit pnpmDepsHash;
      pnpmDepsPname = "openclaw-gateway";
      enableSharp = true;
      extraNativeBuildInputs = [perl makeWrapper];
      extraBuildInputs = [vips];
      extraEnv = {
        NODE_BIN = "${nodejs_22}/bin/node";
        PATCH_CLIPBOARD_SH = "${../scripts/patch-clipboard.sh}";
        PATCH_CLIPBOARD_WRAPPER = "${../scripts/clipboard-wrapper.cjs}";
        OPENCLAW_NIX_STAGE_RUNTIME_DEPS_STRATEGY =
          if normalizedStagedRuntimeDepsPluginIds == null
          then "preserve"
          else "explicit";
        OPENCLAW_NIX_STAGE_RUNTIME_DEPS_PLUGIN_IDS =
          if normalizedStagedRuntimeDepsPluginIds == null
          then ""
          else lib.concatStringsSep "," normalizedStagedRuntimeDepsPluginIds;
        STAGE_BUNDLED_PLUGIN_RUNTIME_DEPS_WRAPPER_MJS = "${../scripts/stage-bundled-plugin-runtime-deps-wrapper.mjs}";
      };
    };
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "openclaw-gateway";
    inherit (common) version;

    src = patchedSrc;
    pnpmDeps = common.pnpmDeps;

    nativeBuildInputs = common.nativeBuildInputs;
    buildInputs = common.buildInputs;

    env =
      common.env
      // {
        PNPM_DEPS = finalAttrs.pnpmDeps;
      };

    postPatch = "${../scripts/gateway-postpatch.sh}";

    buildPhase = "${../scripts/gateway-build.sh}";
    installPhase = "${../scripts/gateway-install.sh}";
    dontFixup = true;
    dontStrip = true;
    dontPatchShebangs = true;

    passthru = {
      inherit (common) pnpmDeps;
    };

    meta = with lib; {
      description = "AI agent gateway (OpenClaw)";
      homepage = "https://github.com/openclaw/openclaw";
      license = licenses.mit;
      platforms = platforms.linux;
      mainProgram = "openclaw";
    };
  })
