{
  lib,
  buildNpmPackage,
  stdenvNoCC,
  src,
  pluginId ? null,
  version ? "0.0.0",
  npmLockfile ? null,
  npmRoot ? ".",
  npmWorkspace ? null,
  npmDepsHash,
  npmDepsFetcherVersion ? 2,
  forceGitDeps ? false,
  makeCacheWritable ? false,
  npmInstallFlags ? [ ],
  npmRebuildFlags ? [ ],
}:
let
  srcPath = toString src;
  manifestRoot = if npmRoot == "." then srcPath else "${srcPath}/${npmRoot}";
  packageJsonPath = "${manifestRoot}/package.json";
  packageLockPathDefault =
    if builtins.pathExists "${manifestRoot}/npm-shrinkwrap.json"
    then "${manifestRoot}/npm-shrinkwrap.json"
    else "${manifestRoot}/package-lock.json";
  packageLockPath =
    if npmLockfile != null
    then toString npmLockfile
    else packageLockPathDefault;
  hasPackageLock = builtins.pathExists packageLockPath;
  packageManifest =
    if builtins.pathExists packageJsonPath
    then builtins.fromJSON (builtins.readFile packageJsonPath)
    else { };
  dependencyNames = builtins.attrNames (packageManifest.dependencies or { });
  preparedSrc =
    if hasPackageLock && packageLockPath != packageLockPathDefault
    then
      stdenvNoCC.mkDerivation {
        pname = "openclaw-plugin-runtime-deps-src";
        inherit src version;
        dontConfigure = true;
        dontBuild = true;
        installPhase = ''
          mkdir -p "$out"
          cp -r ./. "$out/"
          chmod -R u+w "$out"
          mkdir -p "$out/${if npmRoot == "." then "." else npmRoot}"
          cp ${packageLockPath} "$out/${if npmRoot == "." then "." else npmRoot}/${builtins.baseNameOf packageLockPathDefault}"
          find "$out" -type d -exec chmod 0755 {} +
        '';
      }
    else src;
  npmRootPath = if npmRoot == "." then "." else npmRoot;
  runtimeDepsLabel = if pluginId != null then pluginId else "plugin runtime deps";
in
assert lib.assertMsg (builtins.pathExists packageJsonPath) "missing package.json at ${packageJsonPath}";
assert lib.assertMsg hasPackageLock ''
  missing lockfile for OpenClaw plugin runtime deps.
  Expected ${packageLockPathDefault}${lib.optionalString (npmLockfile != null) " or the explicit npmLockfile path"}.
'';
assert lib.assertMsg (dependencyNames != [ ]) ''
  mkPluginRuntimeDepsFromNpmLock requires package.json dependencies at ${packageJsonPath}.
'';
buildNpmPackage {
  pname =
    "openclaw-plugin-runtime-deps"
    + lib.optionalString (pluginId != null) "-${lib.replaceStrings ["/" "@"] ["-" "at-"] pluginId}";
  inherit version;
  src = preparedSrc;

  inherit
    npmRoot
    npmWorkspace
    npmDepsHash
    npmDepsFetcherVersion
    forceGitDeps
    makeCacheWritable
    ;

  npmInstallFlags = [ "--omit=dev" ] ++ npmInstallFlags;
  npmRebuildFlags = [ "--ignore-scripts" ] ++ npmRebuildFlags;
  dontNpmBuild = true;

  installPhase = ''
    if [ ! -d ${npmRootPath}/node_modules ]; then
      echo "node_modules missing after offline npm install for ${runtimeDepsLabel}" >&2
      exit 1
    fi

    while IFS= read -r dependency; do
      [ -n "$dependency" ] || continue
      if [ ! -e ${npmRootPath}/node_modules/"$dependency" ]; then
        echo "vendored runtime deps are missing top-level dependency: $dependency" >&2
        exit 1
      fi
    done << 'DEPENDENCIES_EOF'
    ${lib.concatStringsSep "\n" dependencyNames}
    DEPENDENCIES_EOF

    mkdir -p "$out/node_modules"
    cp -r ${npmRootPath}/node_modules/. "$out/node_modules/"
    find "$out" -type d -exec chmod 0755 {} +
  '';

  passthru.openclaw = {
    inherit pluginId;
    runtimeDepsStrategy = "npm-lock";
    hasVendoredRuntimeDeps = true;
  };

  meta = with lib; {
    description = "Vendored runtime dependencies for an OpenClaw local plugin";
    platforms = platforms.linux;
  };
}
