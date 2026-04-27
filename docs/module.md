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
        openclaw-nixos.nixosModules.systemService
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

The two service adapters intentionally use different option roots.

- `openclaw-nixos.nixosModules.systemService`
  - runs OpenClaw as a system service
  - config root: `services.openclaw`
  - creates the service user/group automatically
  - defaults `stateDir` to `/var/lib/openclaw`
- `openclaw-nixos.nixosModules.userService`
  - runs OpenClaw as a `systemd.user` service for a configured user
  - config root: `services.openclawUser`
  - defaults `stateDir` under the user's home directory
  - expects the host to manage the target user account via `users.users`

Both adapters consume an OpenClaw package. If you need build-time staged bundled plugin runtime deps, override the package itself rather than expecting a separate module option:

```nix
services.openclaw.package =
  openclaw-nixos.lib.withBundledRuntimeDeps {
    package = openclaw-nixos.packages.${pkgs.system}.openclaw-gateway;
    pluginIds = [ "telegram" ];
  };
```

Set `preserveUpstream = true;` to preserve upstream's staged bundled-plugin set, or pass an explicit list to keep the package hermetic for only the plugins you want.

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
For `systemService`: Type `string`, Default: `"openclaw"`

System user to run the service as. Created automatically with `${pkgs.runtimeShell}` (bash on most systems) so that spawned exec sessions and REPL processes work correctly.

For `userService`: use `services.openclawUser.user`, which must point at a user declared in `users.users`.

### `services.openclaw.group`
For `systemService`: Type `string`, Default: `"openclaw"`

System group for the service user.

For `userService`: use `services.openclawUser.group`, which defaults to the configured user's primary group when available, otherwise `users`.

### `services.openclaw.stateDir`
Type: `string`, Default: `"/var/lib/openclaw"` for `systemService`

Base state directory used for the rendered config, mutable extension workaround, and cron job file.

### `services.openclaw.homeDirectory`
Only used by `userService` as `services.openclawUser.homeDirectory`. Defaults to the configured user home when available.

Override the target home directory used for the user-service adapter.

### `services.openclaw.unitName`
Only used by `userService` as `services.openclawUser.unitName`, Default: `"openclaw"`

The `systemd.user` unit name to install for the gateway.

### `services.openclawUser.enableLinger`
Type: `bool`, Default: `true`

Only used by `userService`. When enabled, the module sets `users.users.<name>.linger = true` so the user manager can keep the gateway alive without an active login session.

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

### `systemd.user` service (`userService` only)
The `userService` module installs `systemd.user.services.<unitName>` plus a root-owned activation script that prepares the selected user's state directory before login. The unit is gated with `ConditionUser=<configured user>` and enables linger by default so a headless host can keep the user manager alive.

## Handling Secrets

Sensitive credentials should **not** go in the Nix `config` attrset (world-readable in the Nix store). Use one of these approaches:

1. **`EnvironmentFile`**: Set secrets in a file on the host (e.g. `/var/lib/openclaw/credentials/openclaw.env`) and reference via `systemd.services.openclaw.serviceConfig.EnvironmentFile`.
2. **`configFile`**: Point to a JSON file with restricted permissions.
3. **Both**: The module merges `configFile` (base) + `config` attrset (overlay), letting you keep structure in Nix and secrets in a private file.

## Example: user-service consumer

```nix
{
  users.users.chris = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };

  imports = [ openclaw-nixos.nixosModules.userService ];

  services.openclawUser = {
    enable = true;
    user = "chris";
    port = 3000;
    config = {
      gateway.auth.token = "AUTH_TOKEN";
      memory.enabled = true;
    };
  };
}
```

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
