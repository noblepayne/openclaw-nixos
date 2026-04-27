{
  config,
  pkgs,
  lib,
  openclawUserDefaultPackage ? null,
  ...
}: let
  openclawLib = import ../lib/default.nix {inherit lib;};
  cfg = config.services.openclawUser;
  defaultPackage =
    if openclawUserDefaultPackage != null then
      openclawUserDefaultPackage
    else if pkgs ? openclaw-gateway then
      pkgs.openclaw-gateway
    else
      pkgs.openclaw;
  resolvedPackage = openclawLib.withBundledRuntimeDepsFromPlugins {
    package = cfg.package;
    inherit (cfg) bundledPlugins;
  };
  bundledRuntimeDepsPluginIds = openclawLib.bundledRuntimeDepsPluginIds cfg.bundledPlugins;
  hasConfiguredUser = cfg.user != null;
  hasDeclaredUser =
    hasConfiguredUser
    && builtins.hasAttr cfg.user config.users.users
    && (
      config.users.users.${cfg.user}.isNormalUser
      || config.users.users.${cfg.user}.isSystemUser
      || config.users.users.${cfg.user}.uid != null
    );
  resolvedHomeDirectory =
    if cfg.homeDirectory != null then
      cfg.homeDirectory
    else if hasDeclaredUser && config.users.users.${cfg.user}.home != null then
      config.users.users.${cfg.user}.home
    else if hasConfiguredUser then
      "/home/${cfg.user}"
    else
      "/var/empty";
  resolvedGroup =
    if cfg.group != null then
      cfg.group
    else if hasDeclaredUser && config.users.users.${cfg.user}.group != null then
      config.users.users.${cfg.user}.group
    else
      "users";
  stateDir =
    if cfg.stateDir != null then
      cfg.stateDir
    else
      "${resolvedHomeDirectory}/.local/share/openclaw";
  extensionsDir = openclawLib.mkExtensionsDir stateDir;
  bundledRuntimeDepsDir = openclawLib.mkBundledRuntimeDepsDir stateDir;
  localPluginsDir = openclawLib.mkLocalPluginsDir stateDir;
  distDir = openclawLib.mkDistDir stateDir;
  packageDist = "${resolvedPackage}/lib/openclaw/dist";
  packageNodeModules = "${resolvedPackage}/lib/openclaw/node_modules";
  bundledRuntimeDepsPackage =
    if bundledRuntimeDepsPluginIds == []
    then null
    else
      pkgs.callPackage ../packages/openclaw-bundled-runtime-deps.nix {
        package = resolvedPackage;
        pluginIds = bundledRuntimeDepsPluginIds;
      };
  configPath = openclawLib.mkConfigPath stateDir;
  cronDir = openclawLib.mkCronDir stateDir;
  cronJobsPath = openclawLib.mkCronJobsPath stateDir;
  managedLocalPluginsManifest = "${localPluginsDir}/.openclaw-nix-managed-plugins";
  pluginConfig = openclawLib.renderPluginsConfig {
    inherit (cfg)
      bundledPlugins
      localPlugins
      plugins
      ;
    inherit stateDir;
  };
  enabledLocalPlugins = lib.filterAttrs (_: pluginCfg: pluginCfg.enable) cfg.localPlugins;

  mergedConfig = openclawLib.mergeConfig {
    inherit (cfg) configFile;
    inherit (cfg) config;
    extraConfig = pluginConfig;
  };

  hasConfig = cfg.config != { } || cfg.configFile != null || pluginConfig != { };
  hasCronJobs = cfg.cronJobs != { };
in
{
  options.services.openclawUser = {
    enable = lib.mkEnableOption "OpenClaw gateway user service";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      defaultText = lib.literalExpression "openclaw-nixos.packages.<system>.openclaw-gateway";
      description = "OpenClaw gateway package to use";
    };

    user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "User account that owns the OpenClaw home/state for the user service.";
    };

    group = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Group for state file ownership. Defaults to the configured user's primary group or users.";
    };

    homeDirectory = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Home directory for the OpenClaw user service. Defaults to the configured user's home.";
    };

    stateDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      defaultText = lib.literalExpression ''"/home/<user>/.local/share/openclaw"'';
      description = "State directory for the OpenClaw user service.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Port for the gateway to listen on";
    };

    bind = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address to bind to (use 0.0.0.0 for all interfaces)";
    };

    config = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "OpenClaw configuration as a Nix attrset";
    };

    plugins = lib.mkOption {
      type = lib.types.submodule {
        options = {
          allow = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Plugin IDs to allow under top-level plugins.allow.";
          };
          slots = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = {};
            description = "Plugin slot assignments merged under top-level plugins.slots.";
          };
          entries = lib.mkOption {
            type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
            default = {};
            description = "Plugin entry definitions merged under top-level plugins.entries.";
          };
          installs = lib.mkOption {
            type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
            default = {};
            description = "Plugin install metadata merged under top-level plugins.installs.";
          };
        };
      };
      default = {};
      description = "Declarative plugin config merged into the generated OpenClaw config.";
    };

    bundledPlugins = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
        options = {
          enable = lib.mkEnableOption "bundled OpenClaw plugin ${name}";
          stageRuntimeDeps = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Stage this bundled plugin's runtime dependencies during the package build.";
          };
          config = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = {};
            description = "Merged into plugins.entries.<pluginId>.config when the bundled plugin is enabled.";
          };
          entry = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = {};
            description = "Extra fields merged into plugins.entries.<pluginId> when the bundled plugin is enabled.";
          };
        };
      }));
      default = {};
      description = "Declarative bundled plugin definitions keyed by upstream plugin ID.";
    };

    localPlugins = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to install and configure the local packaged plugin ${name}.";
          };
          allow = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Add this local plugin ID to plugins.allow automatically.";
          };
          package = lib.mkOption {
            type = lib.types.package;
            description = "Packaged local OpenClaw plugin tree to install for ${name}.";
          };
          version = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Version to render into plugins.installs.<pluginId>.version. Defaults to the package version when available.";
          };
          config = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = {};
            description = "Merged into plugins.entries.<pluginId>.config when the local plugin is enabled.";
          };
          entry = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = {};
            description = "Extra fields merged into plugins.entries.<pluginId> when the local plugin is enabled.";
          };
          install = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = {};
            description = "Extra fields merged into plugins.installs.<pluginId>.";
          };
        };
      }));
      default = {};
      description = "Declarative local packaged plugins keyed by plugin ID.";
    };

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to an openclaw.json config file. Merged with config attrset if both set (config takes priority).";
    };

    mutableExtensionsDir = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Copy extension files from the read-only Nix store into a mutable user state directory.
        Required for upstream versions that enforce plugin path boundary validation.
      '';
    };

    cronJobs = lib.mkOption {
      type = lib.types.submodule {
        freeformType = lib.types.attrsOf lib.types.anything;
        options = {
          version = lib.mkOption {
            type = lib.types.int;
            default = 1;
            description = "Cron jobs file format version";
          };
          jobs = lib.mkOption {
            type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
            default = [ ];
            description = "List of cron job definitions";
          };
        };
      };
      default = { };
      description = "Cron job definitions. Written to the user state directory.";
    };

    unitName = lib.mkOption {
      type = lib.types.str;
      default = "openclaw";
      description = "systemd user unit name for the OpenClaw gateway.";
    };

    enableLinger = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable linger for the configured user so the gateway can run without an active login session.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.user != null;
        message = "services.openclawUser.user must be set when using the userService module.";
      }
      {
        assertion = hasDeclaredUser;
        message = "services.openclawUser.user must reference a user declared in users.users so the module can resolve home and linger settings.";
      }
    ] ++ lib.mapAttrsToList (
      pluginId: pluginCfg:
      let
        pluginMeta = pluginCfg.package.passthru.openclaw or { };
      in
      {
        assertion = (pluginMeta.pluginId or null) == pluginId;
        message = "services.openclawUser.localPlugins.${pluginId}.package must expose passthru.openclaw.pluginId = \"${pluginId}\".";
      }
    ) enabledLocalPlugins ++ lib.mapAttrsToList (
      pluginId: pluginCfg:
      let
        pluginMeta = pluginCfg.package.passthru.openclaw or { };
      in
      {
        assertion =
          !(pluginMeta.requiresRuntimeDeps or false)
          || (pluginMeta.hasVendoredRuntimeDeps or false);
        message = "services.openclawUser.localPlugins.${pluginId}.package declares runtime deps but does not vendor them. Build it with openclaw-nixos.lib.mkPluginRuntimeDepsFromNpmLock or mkPluginPackage runtimeDeps.npm.";
      }
    ) enabledLocalPlugins;

    users.users.${cfg.user}.linger = lib.mkDefault cfg.enableLinger;

    system.activationScripts."openclaw-user-setup-${cfg.user}" = let
      setupExtensions = lib.optionalString cfg.mutableExtensionsDir ''
        rm -rf ${distDir}
        mkdir -p ${distDir}
        cp -r ${packageDist}/* ${distDir}/
        ln -sfn ${packageNodeModules} ${distDir}/node_modules
      '';

      setupBundledRuntimeDeps = lib.optionalString (bundledRuntimeDepsPackage != null) ''
        rm -rf ${bundledRuntimeDepsDir}
        mkdir -p ${bundledRuntimeDepsDir}
        cp -r ${bundledRuntimeDepsPackage}/. ${bundledRuntimeDepsDir}/
      '';

      setupLocalPlugins = ''
        mkdir -p ${localPluginsDir}
        if [ -f ${managedLocalPluginsManifest} ]; then
          while IFS= read -r plugin_id; do
            [ -n "$plugin_id" ] || continue
            rm -rf ${localPluginsDir}/"$plugin_id"
          done < ${managedLocalPluginsManifest}
        fi
        cat > ${managedLocalPluginsManifest}.tmp << 'LOCAL_PLUGINS_EOF'
        ${lib.concatStringsSep "\n" (builtins.attrNames enabledLocalPlugins)}
        LOCAL_PLUGINS_EOF
        mv ${managedLocalPluginsManifest}.tmp ${managedLocalPluginsManifest}
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (pluginId: pluginCfg: ''
          mkdir -p ${openclawLib.mkLocalPluginInstallPath stateDir pluginId}
          cp -r ${pluginCfg.package}/. ${openclawLib.mkLocalPluginInstallPath stateDir pluginId}/
        '') enabledLocalPlugins)}
      '';

      setupConfig = lib.optionalString hasConfig ''
        mkdir -p $(dirname ${configPath})
        cat > ${configPath}.tmp << 'CONFIG_EOF'
        ${builtins.toJSON mergedConfig}
        CONFIG_EOF
        mv ${configPath}.tmp ${configPath}
      '';

      setupCron = lib.optionalString hasCronJobs ''
        mkdir -p ${cronDir}
        cat > ${cronJobsPath}.tmp << 'CRON_EOF'
        ${builtins.toJSON cfg.cronJobs}
        CRON_EOF
        mv ${cronJobsPath}.tmp ${cronJobsPath}
      '';

      steps = lib.filter (s: s != "") [
        "install -d -m 0755 -o ${cfg.user} -g ${resolvedGroup} ${resolvedHomeDirectory}"
        "install -d -m 0755 -o ${cfg.user} -g ${resolvedGroup} ${stateDir}"
        setupConfig
        setupCron
        setupExtensions
        setupBundledRuntimeDeps
        setupLocalPlugins
        "chown -R ${cfg.user}:${resolvedGroup} ${stateDir}"
      ];
    in
      lib.stringAfter [ "users" ] (lib.concatStringsSep "\n\n" steps);

    systemd.user.services.${cfg.unitName} = {
      description = "OpenClaw AI Gateway";
      wantedBy = [ "default.target" ];
      after = [ "network.target" ];
      unitConfig.ConditionUser = cfg.user;
      serviceConfig = {
        Type = "simple";
        ExecStart = "${resolvedPackage}/bin/openclaw gateway";
        WorkingDirectory = stateDir;
        Restart = "always";
        RestartSec = 5;
      };
      environment =
        {
          PORT = toString cfg.port;
          BIND_ADDRESS = cfg.bind;
          OPENCLAW_NIX_MODE = "1";
          HOME = resolvedHomeDirectory;
          OPENCLAW_CONFIG_PATH = configPath;
        }
        // lib.optionalAttrs cfg.mutableExtensionsDir {
          OPENCLAW_BUNDLED_PLUGINS_DIR = extensionsDir;
        }
        // lib.optionalAttrs (bundledRuntimeDepsPackage != null) {
          OPENCLAW_PLUGIN_STAGE_DIR = bundledRuntimeDepsDir;
        }
        // lib.optionalAttrs hasConfig {
          CONFIG_HASH = builtins.hashString "sha256" (builtins.toJSON mergedConfig);
        };
    };
  };
}
