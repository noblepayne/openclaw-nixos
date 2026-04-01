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
      default = pkgs.openclaw;
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
            type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
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

    # Runs as root to set up mutable state from the Nix store.
    # This is a separate oneshot service (runs as root, no sandboxing)
    # that the main gateway service depends on.
    systemd.services.openclaw-setup = {
      description = "OpenClaw state setup";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
      };
      wantedBy = ["openclaw.service"];
      before = ["openclaw.service"];

      script = let
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
          setupConfig
          setupCron
          setupExtensions
          "chown -R ${cfg.user}:${cfg.group} ${stateDir}"
        ];
      in
        lib.concatStringsSep "\n\n" steps;
    };

    systemd.services.openclaw = {
      description = lib.mkDefault "OpenClaw AI Gateway";
      wantedBy = lib.mkDefault ["multi-user.target"];
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

      serviceConfig = {
        Type = lib.mkDefault "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = lib.mkDefault stateDir;
        ExecStart = lib.mkDefault "${cfg.package}/bin/openclaw gateway";
        Restart = lib.mkDefault "always";
        RestartSec = lib.mkDefault 5;

        # Hardening
        NoNewPrivileges = lib.mkDefault true;
        ProtectSystem = lib.mkDefault "strict";
        ProtectHome = lib.mkDefault true;
        PrivateTmp = lib.mkDefault true;
        ReadWritePaths = [stateDir];
      };

      preStart = "chown -R ${cfg.user}:${cfg.group} ${stateDir}";
    };
  };
}
