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
  node-gyp,
  git,
  zstd,
}:
# Shared build plumbing for OpenClaw gateway.
# Adapted from nix-openclaw, linux x86_64 only.
{
  pname,
  src,
  pnpmDepsHash,
  pnpmDepsPname ? "openclaw-gateway",
  enableSharp ? false,
  extraNativeBuildInputs ? [],
  extraBuildInputs ? [],
  extraEnv ? {},
}: let
  pnpmPlatform = stdenv.hostPlatform.node.platform;
  pnpmArch = stdenv.hostPlatform.node.arch;

  version = "2026.4.29";

  nodeAddonApi = fetchurl {
    url = "https://registry.npmjs.org/node-addon-api/-/node-addon-api-8.5.0.tgz";
    hash = "sha256-0S8HyBYig7YhNVGFXx2o2sFiMxN0YpgwteZA8TDweRA=";
  };

  pnpmDeps = fetchPnpmDeps {
    pname = pnpmDepsPname;
    inherit version src;
    pnpm = pnpm_10;
    hash = pnpmDepsHash;
    fetcherVersion = 3;
    npm_config_arch = pnpmArch;
    npm_config_platform = pnpmPlatform;
    nativeBuildInputs = [git];
  };

  envBase = {
    npm_config_arch = pnpmArch;
    npm_config_platform = pnpmPlatform;
    PNPM_CONFIG_MANAGE_PACKAGE_MANAGER_VERSIONS = "false";
    npm_config_nodedir = nodejs_22;
    npm_config_python = python3;
    NODE_PATH = "${nodeAddonApi}/lib/node_modules:${node-gyp}/lib/node_modules";
    PNPM_DEPS = pnpmDeps;
    NODE_GYP_WRAPPER_SH = "${../scripts/node-gyp-wrapper.sh}";
    GATEWAY_PREBUILD_SH = "${../scripts/gateway-prebuild.sh}";
    PROMOTE_PNPM_INTEGRITY_SH = "${../scripts/promote-pnpm-integrity.sh}";
    REMOVE_PACKAGE_MANAGER_FIELD_SH = "${../scripts/remove-package-manager-field.sh}";
    STDENV_SETUP = "${stdenv}/setup";
  };
in {
  inherit version pnpmDeps pnpmPlatform pnpmArch nodeAddonApi;

  nativeBuildInputs =
    [
      nodejs_22
      pnpm_10
      pkg-config
      jq
      python3
      node-gyp
      zstd
    ]
    ++ extraNativeBuildInputs;

  buildInputs = extraBuildInputs;

  env =
    envBase
    // (lib.optionalAttrs enableSharp {SHARP_IGNORE_GLOBAL_LIBVIPS = "1";})
    // extraEnv;
}
