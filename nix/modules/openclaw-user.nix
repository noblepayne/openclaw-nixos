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
  distDir = openclawLib.mkDistDir stateDir;
  packageDist = "${resolvedPackage}/lib/openclaw/dist";
  packageNodeModules = "${resolvedPackage}/lib/openclaw/node_modules";
  configPath = openclawLib.mkConfigPath stateDir;
  cronDir = openclawLib.mkCronDir stateDir;
  cronJobsPath = openclawLib.mkCronJobsPath stateDir;
  pluginConfig = openclawLib.renderPluginsConfig {
    inherit (cfg)
      bundledPlugins
      plugins
      ;
  };

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
    ];

    users.users.${cfg.user}.linger = lib.mkDefault cfg.enableLinger;

    system.activationScripts."openclaw-user-setup-${cfg.user}" = let
      setupExtensions = lib.optionalString cfg.mutableExtensionsDir ''
        rm -rf ${distDir}
        mkdir -p ${distDir}
        cp -r ${packageDist}/* ${distDir}/
        ln -sfn ${packageNodeModules} ${distDir}/node_modules
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
        // lib.optionalAttrs hasConfig {
          CONFIG_HASH = builtins.hashString "sha256" (builtins.toJSON mergedConfig);
        };
    };
  };
}
