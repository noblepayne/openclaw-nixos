{ lib }:
let
  readConfigFile =
    configFile:
    if configFile != null then
      builtins.fromJSON (builtins.readFile configFile)
    else
      { };

  mergeConfigLayers = layers: lib.foldl' lib.recursiveUpdate { } layers;

  mergeConfig =
    {
      configFile ? null,
      extraConfig ? { },
      config ? { },
    }:
    mergeConfigLayers [
      (readConfigFile configFile)
      extraConfig
      config
    ];

  renderConfigJson =
    {
      configFile ? null,
      extraConfig ? { },
      config ? { },
    }:
    builtins.toJSON (mergeConfig {
      inherit
        configFile
        extraConfig
        config
        ;
    });

  renderCronJobsJson =
    {
      cronJobs ? { },
    }:
    builtins.toJSON cronJobs;

  renderBundledPluginEntry =
    pluginId: pluginCfg:
    lib.recursiveUpdate
      {
        enabled = true;
      }
      (lib.recursiveUpdate
        (pluginCfg.entry or { })
        (lib.optionalAttrs (pluginCfg.config or { } != { }) {
          config = pluginCfg.config;
        }));

  renderPluginsConfig =
    {
      bundledPlugins ? { },
      plugins ? {
        allow = [ ];
        slots = { };
        entries = { };
        installs = { };
      },
    }:
    let
      enabledBundledPlugins = lib.filterAttrs (_: pluginCfg: pluginCfg.enable) bundledPlugins;
      renderedBundledEntries = lib.mapAttrs renderBundledPluginEntry enabledBundledPlugins;
      allow =
        lib.unique ((plugins.allow or [ ]) ++ (builtins.attrNames enabledBundledPlugins));
      slots = plugins.slots or { };
      entries = lib.recursiveUpdate renderedBundledEntries (plugins.entries or { });
      installs = plugins.installs or { };
      renderedPlugins =
        (lib.optionalAttrs (allow != [ ]) { inherit allow; })
        // (lib.optionalAttrs (slots != { }) { inherit slots; })
        // (lib.optionalAttrs (entries != { }) { inherit entries; })
        // (lib.optionalAttrs (installs != { }) { inherit installs; });
    in
    lib.optionalAttrs (renderedPlugins != { }) {
      plugins = renderedPlugins;
    };

  bundledRuntimeDepsPluginIds =
    bundledPlugins:
    lib.sort builtins.lessThan (
      builtins.attrNames (
        lib.filterAttrs (_: pluginCfg: pluginCfg.enable && pluginCfg.stageRuntimeDeps) bundledPlugins
      )
    );

  withBundledRuntimeDeps =
    {
      package,
      pluginIds ? [ ],
      preserveUpstream ? false,
    }:
    package.override {
      stagedRuntimeDepsPluginIds =
        if preserveUpstream
        then null
        else pluginIds;
    };

  withBundledRuntimeDepsFromPlugins =
    {
      package,
      bundledPlugins ? { },
      preserveUpstream ? false,
    }:
    withBundledRuntimeDeps {
      inherit
        package
        preserveUpstream
        ;
      pluginIds = bundledRuntimeDepsPluginIds bundledPlugins;
    };

  mkConfigPath = stateDir: "${stateDir}/openclaw.json";
  mkCronDir = stateDir: "${stateDir}/cron";
  mkCronJobsPath = stateDir: "${mkCronDir stateDir}/jobs.json";
  mkDistDir = stateDir: "${stateDir}/dist";
  mkExtensionsDir = stateDir: "${mkDistDir stateDir}/extensions";
in
{
  inherit
    mergeConfig
    renderConfigJson
    renderCronJobsJson
    renderPluginsConfig
    bundledRuntimeDepsPluginIds
    withBundledRuntimeDeps
    withBundledRuntimeDepsFromPlugins
    mkConfigPath
    mkCronDir
    mkCronJobsPath
    mkDistDir
    mkExtensionsDir
    ;
}
