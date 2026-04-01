# NixOS Module

## Enabling

Add this flake to your system configuration:

```nix
{
  inputs.openclaw-nixos.url = "github:noblepayne/openclaw-nixos";

  outputs = { nixpkgs, openclaw-nixos, ... }: {
    nixosConfigurations.my-agent = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        openclaw-nixos.nixosModules.default
        {
          services.openclaw = {
            enable = true;
            port = 3000;
            config = {
              channels.telegram.enabled = true;
              gateway.auth.token = "AUTH_TOKEN";
              memory.enabled = true;
            };
          };
        }
      ];
    };
  };
}
```

## Configuration Options

### `services.openclaw.enable`
Type: `bool`, Default: `false`

Enable the OpenClaw gateway service.

### `services.openclaw.package`
Type: `package`, Default: `pkgs.openclaw`

The OpenClaw package to use. The overlay also exports this as `pkgs.openclaw-gateway`.

### `services.openclaw.port`
Type: `port`, Default: `3000`

Port for the gateway to listen on.

### `services.openclaw.bind`
Type: `string`, Default: `"127.0.0.1"`

Address to bind to. Use `"0.0.0.0"` for all interfaces.

### `services.openclaw.config`
Type: `attrs`, Default: `{}`

OpenClaw configuration as a Nix attrset. Merged with `configFile` if both are set (attrset wins on conflicts). Written to `/var/lib/openclaw/openclaw.json` by the setup service.

```nix
services.openclaw.config = {
  channels.telegram = {
    enabled = true;
    token = "BOT_TOKEN";
  };
  gateway.auth.token = "AUTH_TOKEN";
  providers.openai.apiKey = "sk-...";
  memory.enabled = true;
};
```

### `services.openclaw.configFile`
Type: `path`, Default: `null`

Path to an existing `openclaw.json` file. Its contents are merged with `config` (attrset wins on conflicts). The merged result is written to `/var/lib/openclaw/openclaw.json`.

### `services.openclaw.cronJobs`
Type: `submodule { version; jobs; }`, Default: `{}`

Defines scheduled jobs written to `/var/lib/openclaw/cron/jobs.json`. Uses the same schema as OpenClaw's internal cron system.

```nix
services.openclaw.cronJobs = {
  version = 1;
  jobs = [
    {
      name = "morning-briefing";
      schedule = { cron = "0 14 * * *"; };  # UTC timezone
      command = { run = ["node" "scripts/briefing.cjs"]; };
    }
  ];
};
```

### `services.openclaw.mutableExtensionsDir`
Type: `bool`, Default: `true`

When enabled, copies bundled extensions from the read-only Nix store to `/var/lib/openclaw/dist/` and sets `OPENCLAW_BUNDLED_PLUGINS_DIR` to point there.

This is **required** for upstream OpenClaw versions that enforce plugin path boundary validation, which rejects Nix store paths. Handled by the `openclaw-setup` oneshot service that runs before each gateway start.

Disable only after the upstream fix (PR #42900) is merged and released.

### `services.openclaw.openFirewall`
Type: `bool`, Default: `false`

Open the firewall for the configured port.

### `services.openclaw.user`
Type: `string`, Default: `"openclaw"`

System user to run the service as. Created automatically with `${pkgs.runtimeShell}` (bash on most systems) so that spawned exec sessions and REPL processes work correctly.

### `services.openclaw.group`
Type: `string`, Default: `"openclaw"`

System group for the service user.

## Services Created

### `openclaw.service`
The main gateway process. Restart policy: `always` with 5s delay. Hardened with `NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome=true`, `PrivateTmp=true`.

### `openclaw-setup.service`
A oneshot service that runs as root before the gateway starts. Handles:
- Copies extensions from the Nix store to `/var/lib/openclaw/dist/`
- Symlinks `node_modules` from the store into the mutable `dist/`
- Writes merged config to `/var/lib/openclaw/openclaw.json`
- Writes cron jobs to `/var/lib/openclaw/cron/jobs.json`
- Chowns state directory to the service user

On NixOS rebuild: the setup service re-runs because the unit file changes (new store paths). On manual service restart: the mutable extension directory is still valid — no re-copy needed.

## Handling Secrets

Sensitive credentials should **not** go in the Nix `config` attrset (world-readable in the Nix store). Use one of these approaches:

1. **`EnvironmentFile`**: Set secrets in a file on the host (e.g. `/var/lib/openclaw/credentials/openclaw.env`) and reference via `systemd.services.openclaw.serviceConfig.EnvironmentFile`.
2. **`configFile`**: Point to a JSON file with restricted permissions.
3. **Both**: The module merges `configFile` (base) + `config` attrset (overlay), letting you keep structure in Nix and secrets in a private file.

## Example: full server setup

```nix
{
  services.openclaw = {
    enable = true;
    port = 3000;
    bind = "0.0.0.0";
    openFirewall = true;

    config = {
      channels.telegram = {
        enabled = true;
        token = "BOT_TOKEN";
      };
      gateway = {
        auth.token = "AUTH_TOKEN";
        cors.origins = ["https://my-dashboard.example.com"];
      };
      providers = {
        openai.apiKey = "sk-...";
        anthropic.apiKey = "sk-ant-...";
      };
      memory = {
        enabled = true;
        qmd.enabled = true;
      };
    };

    # Scheduled jobs
    cronJobs = {
      version = 1;
      jobs = [
        {
          name = "morning-briefing";
          schedule = { cron = "0 14 * * *"; };
          command = { run = ["node" "scripts/briefing.cjs"]; };
        }
      ];
    };
  };
}
```

## Troubleshooting

### Service won't start
```bash
journalctl -u openclaw -f
journalctl -u openclaw-setup -f
```
Check for:
- Missing config (no `config` or `configFile` set)
- Extension copy failures (check `openclaw-setup` logs)
- Port conflicts

### "Unsafe plugin manifest path" error
The `mutableExtensionsDir` workaround should handle this. If you see it anyway:
```bash
systemctl restart openclaw-setup
journalctl -u openclaw-setup -f
```

### Config not being read
The merged config is written to `/var/lib/openclaw/openclaw.json` by the setup service. Check:
- File exists and has correct content
- `OPENCLAW_CONFIG_PATH=/var/lib/openclaw/openclaw.json` is set (default)
- Service user can read the file

### Extension changes not picked up
The `openclaw-setup` service re-copies extensions on NixOS rebuild. If manually restarting:
```bash
systemctl restart openclaw-setup openclaw
```

### State got corrupted
```bash
systemctl stop openclaw
rm -rf /var/lib/openclaw/dist
systemctl start openclaw-setup openclaw
```
