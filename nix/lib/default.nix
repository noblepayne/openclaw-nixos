{lib}: let
  readConfigFile = configFile:
    if configFile != null
    then builtins.fromJSON (builtins.readFile configFile)
    else {};

  mergeConfigLayers = layers: lib.foldl' lib.recursiveUpdate {} layers;

  mergeConfig = {
    configFile ? null,
    extraConfig ? {},
    config ? {},
  }:
    mergeConfigLayers [
      (readConfigFile configFile)
      extraConfig
      config
    ];

  renderConfigJson = {
    configFile ? null,
    extraConfig ? {},
    config ? {},
  }:
    builtins.toJSON (mergeConfig {
      inherit
        configFile
        extraConfig
        config
        ;
    });

  renderCronJobsJson = {cronJobs ? {}}:
    builtins.toJSON cronJobs;

  renderBundledPluginEntry = pluginId: pluginCfg:
    lib.recursiveUpdate
    {
      enabled = true;
    }
    (lib.recursiveUpdate
      (pluginCfg.entry or {})
      (lib.optionalAttrs (pluginCfg.config or {} != {}) {
        config = pluginCfg.config;
      }));

  renderLocalPluginEntry = pluginId: pluginCfg:
    lib.recursiveUpdate
    {
      enabled = true;
    }
    (lib.recursiveUpdate
      (pluginCfg.entry or {})
      (lib.optionalAttrs (pluginCfg.config or {} != {}) {
        config = pluginCfg.config;
      }));

  mkLocalPluginsDir = stateDir: "${stateDir}/extensions";
  mkLocalPluginInstallPath = stateDir: pluginId: "${mkLocalPluginsDir stateDir}/${pluginId}";

  renderLocalPluginInstall = stateDir: pluginId: pluginCfg: let
    renderedVersion =
      if (pluginCfg.version or null) != null
      then pluginCfg.version
      else pluginCfg.package.version or null;
  in
    (lib.optionalAttrs true {
      source = "path";
      sourcePath = toString pluginCfg.package;
      installPath = mkLocalPluginInstallPath stateDir pluginId;
    })
    // (lib.optionalAttrs (renderedVersion != null) {
      version = renderedVersion;
    })
    // (pluginCfg.install or {});

  renderPluginsConfig = {
    bundledPlugins ? {},
    localPlugins ? {},
    stateDir,
    plugins ? {
      allow = [];
      slots = {};
      entries = {};
      installs = {};
    },
  }: let
    enabledBundledPlugins = lib.filterAttrs (_: pluginCfg: pluginCfg.enable or false) bundledPlugins;
    enabledLocalPlugins = lib.filterAttrs (_: pluginCfg: pluginCfg.enable or true) localPlugins;
    renderedBundledEntries = lib.mapAttrs renderBundledPluginEntry enabledBundledPlugins;
    renderedLocalEntries = lib.mapAttrs renderLocalPluginEntry enabledLocalPlugins;
    renderedLocalInstalls =
      lib.mapAttrs (renderLocalPluginInstall stateDir) enabledLocalPlugins;
    allow = lib.unique (
      (plugins.allow or [])
      ++ (builtins.attrNames enabledBundledPlugins)
      ++ (builtins.attrNames (lib.filterAttrs (_: pluginCfg: pluginCfg.allow or true) enabledLocalPlugins))
    );
    slots = plugins.slots or {};
    entries =
      lib.recursiveUpdate
      (lib.recursiveUpdate renderedBundledEntries renderedLocalEntries)
      (plugins.entries or {});
    installs = lib.recursiveUpdate renderedLocalInstalls (plugins.installs or {});
    renderedPlugins =
      (lib.optionalAttrs (allow != []) {inherit allow;})
      // (lib.optionalAttrs (slots != {}) {inherit slots;})
      // (lib.optionalAttrs (entries != {}) {inherit entries;})
      // (lib.optionalAttrs (installs != {}) {inherit installs;});
  in
    lib.optionalAttrs (renderedPlugins != {}) {
      plugins = renderedPlugins;
    };

  bundledRuntimeDepsPluginIds = bundledPlugins:
    lib.sort builtins.lessThan (
      builtins.attrNames (
        lib.filterAttrs (_: pluginCfg: (pluginCfg.enable or false) && (pluginCfg.stageRuntimeDeps or false)) bundledPlugins
      )
    );

  enabledBundledPluginIds = bundledPlugins:
    lib.sort builtins.lessThan (
      builtins.attrNames (
        lib.filterAttrs (_: pluginCfg: pluginCfg.enable or false) bundledPlugins
      )
    );

  bundledPluginPackageIds = {
    bundledPlugins ? {},
    extraPluginIds ? [],
  }:
    lib.sort builtins.lessThan (
      lib.unique (
        (enabledBundledPluginIds bundledPlugins)
        ++ extraPluginIds
      )
    );

  mkPluginProfile = {
    bundledPlugins ? {},
    extraBundledPluginIds ? [],
    localPlugins ? {},
    plugins ? {},
    config ? {},
    cronJobs ? {},
  }: {
    inherit
      bundledPlugins
      extraBundledPluginIds
      localPlugins
      plugins
      config
      cronJobs
      ;
  };

  mergePluginProfiles = profiles: let
    mergeOne = acc: profile: let
      merged = lib.recursiveUpdate acc profile;
      accPlugins = acc.plugins or {};
      profilePlugins = profile.plugins or {};
      mergedPlugins = merged.plugins or {};
    in
      merged
      // {
        extraBundledPluginIds = lib.unique (
          (acc.extraBundledPluginIds or [])
          ++ (profile.extraBundledPluginIds or [])
        );
        plugins =
          mergedPlugins
          // (lib.optionalAttrs (mergedPlugins ? allow || accPlugins ? allow || profilePlugins ? allow) {
            allow = lib.unique (
              (accPlugins.allow or [])
              ++ (profilePlugins.allow or [])
            );
          });
      };
  in
    lib.foldl' mergeOne {} profiles;

  pluginProfiles = let
    chat = mkPluginProfile {
      extraBundledPluginIds = ["speech-core"];
      bundledPlugins.telegram = {
        enable = lib.mkDefault true;
        stageRuntimeDeps = lib.mkDefault true;
      };
      bundledPlugins.discord = {
        enable = lib.mkDefault true;
        stageRuntimeDeps = lib.mkDefault true;
      };
    };
    browserAutomation = mkPluginProfile {
      bundledPlugins.browser = {
        enable = lib.mkDefault true;
        stageRuntimeDeps = lib.mkDefault true;
      };
    };
    acp = mkPluginProfile {
      bundledPlugins.acpx = {
        enable = lib.mkDefault true;
        stageRuntimeDeps = lib.mkDefault true;
      };
    };
  in rec {
    inherit
      chat
      browserAutomation
      acp
      ;

    default = mergePluginProfiles [
      chat
    ];
  };

  withBundledRuntimeDeps = {
    package,
    pluginIds ? [],
    preserveUpstream ? false,
  }:
    package.override {
      stagedRuntimeDepsPluginIds =
        if preserveUpstream
        then null
        else pluginIds;
    };

  withBundledRuntimeDepsFromPlugins = {
    package,
    bundledPlugins ? {},
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
  mkBundledRuntimeDepsDir = stateDir: "${stateDir}/plugin-runtime-deps";
in {
  inherit
    mergeConfig
    renderConfigJson
    renderCronJobsJson
    renderPluginsConfig
    enabledBundledPluginIds
    bundledPluginPackageIds
    bundledRuntimeDepsPluginIds
    mkPluginProfile
    mergePluginProfiles
    pluginProfiles
    withBundledRuntimeDeps
    withBundledRuntimeDepsFromPlugins
    mkConfigPath
    mkCronDir
    mkCronJobsPath
    mkDistDir
    mkExtensionsDir
    mkBundledRuntimeDepsDir
    mkLocalPluginsDir
    mkLocalPluginInstallPath
    ;
}
