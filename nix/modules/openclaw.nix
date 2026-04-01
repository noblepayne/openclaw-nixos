{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.openclaw;
  stateDir = "/var/lib/openclaw";

  # Merge config attrset and configFile into a single JSON file
  configFile = let
    hasAttrset = cfg.config != {};
    hasFile = cfg.configFile != null;
  in
    if hasAttrset && hasFile then
      pkgs.writeText "openclaw.json" (builtins.toJSON (
        (builtins.fromJSON (builtins.readFile cfg.configFile)) // cfg.config
      ))
    else if hasAttrset then
      pkgs.writeText "openclaw.json" (builtins.toJSON cfg.config)
    else if hasFile then
      cfg.configFile
    else
      null;
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
      type = lib.types.attrs;
      default = {};
      description = "OpenClaw configuration as a Nix attrset (merged with configFile if both set)";
      example = {
        channels.telegram.token = "BOT_TOKEN";
        gateway.auth.token = "AUTH_TOKEN";
      };
    };

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to an openclaw.json config file (merged with config attrset if both set)";
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
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = stateDir;
      createHome = true;
    };

    users.groups.${cfg.group} = {};

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.port];

    systemd.services.openclaw = {
      description = "OpenClaw AI Gateway";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];

      environment = {
        PORT = toString cfg.port;
        BIND_ADDRESS = cfg.bind;
        OPENCLAW_NIX_MODE = "1";
        HOME = stateDir;
      } // (lib.optionalAttrs (configFile != null) {
        OPENCLAW_CONFIG_FILE = configFile;
      });

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = stateDir;
        ExecStart = "${cfg.package}/bin/openclaw";
        Restart = "always";
        RestartSec = 5;

        # Hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = [stateDir];
      };

      preStart = lib.optionalString (configFile != null) ''
        mkdir -p ${stateDir}/.openclaw
        cp ${configFile} ${stateDir}/.openclaw/openclaw.json
        chmod 600 ${stateDir}/.openclaw/openclaw.json
        chown -R ${cfg.user}:${cfg.group} ${stateDir}
      '';
    };
  };
}
