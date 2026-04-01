{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.openclaw;
  stateDir = "/var/lib/openclaw";
  extensionsDir = "${stateDir}/dist/extensions";
  distDir = "${stateDir}/dist";
  packageDist = "${cfg.package}/lib/openclaw/dist";
  packageNodeModules = "${cfg.package}/lib/openclaw/node_modules";
  configPath = "${stateDir}/openclaw.json";
  cronDir = "${stateDir}/cron";
  cronJobsPath = "${cronDir}/jobs.json";

  # Merge config: base (from file or attrset) + overlay (from attrset)
  # Priority order: configFile < config attrset < environment overrides
  configFileContent =
    if cfg.configFile != null
    then builtins.fromJSON (builtins.readFile cfg.configFile)
    else {};

  mergedConfig = lib.recursiveUpdate configFileContent cfg.config;

  hasConfig = cfg.config != {};

  hasCronJobs = cfg.cronJobs != {};
in {
  options.services.openclaw = {
    enable = lib.mkEnableOption "OpenClaw gateway";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.openclaw-gateway;
      description = "OpenClaw gateway package to use";
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
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = {};
      description = "OpenClaw configuration as a Nix attrset";
      example = {
        channels.telegram.token = "BOT_TOKEN";
        gateway.auth.token = "AUTH_TOKEN";
      };
    };

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to an openclaw.json config file. Merged with config attrset if both set (config takes priority).";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the firewall for the gateway port";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "openclaw";
      description = "User to run OpenClaw as";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "openclaw";
      description = "Group to run OpenClaw as";
    };

    mutableExtensionsDir = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Copy extension files from the read-only Nix store into a mutable state directory.
        Required for upstream versions that enforce plugin path boundary validation.
        Disable only if your OpenClaw version has the upstream fix merged.
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
            type = lib.types.listOf lib.types.attrsOf lib.types.anything;
            default = [];
            description = "List of cron job definitions";
          };
        };
      };
      default = {};
      description = "Cron job definitions. Written to {stateDir}/cron/jobs.json";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users."${cfg.user}" = {
      isSystemUser = true;
      group = cfg.group;
      home = stateDir;
      createHome = true;
    };

    users.groups."${cfg.group}" = {};

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.port];

    systemd.services.openclaw = {
      description = "OpenClaw AI Gateway";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];

      environment =
        {
          PORT = toString cfg.port;
          BIND_ADDRESS = cfg.bind;
          OPENCLAW_NIX_MODE = "1";
          HOME = stateDir;
          OPENCLAW_CONFIG_PATH = configPath;
        }
        // lib.optionalAttrs cfg.mutableExtensionsDir {
          OPENCLAW_BUNDLED_PLUGINS_DIR = extensionsDir;
        }
        // lib.optionalAttrs hasConfig {
          CONFIG_HASH = builtins.hashString "sha256" (builtins.toJSON mergedConfig);
        };

      preStart = let
        setupConfig = lib.optionalString hasConfig ''
          # Write merged config to state dir
          mkdir -p $(dirname ${configPath})
          cat > ${configPath}.tmp << 'CONFIG_EOF'
          ${builtins.toJSON mergedConfig}
          CONFIG_EOF
          mv ${configPath}.tmp ${configPath}
        '';

        setupCron = lib.optionalString hasCronJobs ''
          # Write cron jobs
          mkdir -p ${cronDir}
          cat > ${cronJobsPath}.tmp << 'CRON_EOF'
          ${builtins.toJSON cfg.cronJobs}
          CRON_EOF
          mv ${cronJobsPath}.tmp ${cronJobsPath}
        '';

        setupExtensions = lib.optionalString cfg.mutableExtensionsDir ''
          # Workaround for upstream plugin path boundary validation.
          # Nix store paths fail the "unsafe plugin manifest path" check.
          # Copy extensions to mutable storage and symlink node_modules.
          rm -rf ${distDir}
          mkdir -p ${distDir}
          cp -r ${packageDist}/* ${distDir}/
          ln -sfn ${packageNodeModules} ${distDir}/node_modules
        '';

        steps = lib.filter (s: s != "") [
          setupConfig
          setupCron
          setupExtensions
          "chown -R ${cfg.user}:${cfg.group} ${stateDir}"
        ];
      in
        lib.mkIf (steps != []) (lib.concatStringsSep "\n\n" steps);
    };
  };
}
