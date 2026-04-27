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

Both adapters consume an OpenClaw package, but the preferred interface for bundled plugins is the declarative module surface:

```nix
services.openclaw.bundledPlugins.telegram = {
  enable = true;
  stageRuntimeDeps = true;
  config.botToken = "BOT_TOKEN";
};
```

When you enable bundled plugins this way, the module does three things:

- merges the plugin ID into `plugins.allow`
- renders `plugins.entries.<id>` from `config` and `entry`
- builds a filtered bundled-plugin artifact containing only the enabled bundled plugin IDs

If `stageRuntimeDeps = true`, the module also prepares a build-time bundled runtime-deps closure for that plugin and assembles a live stage root under `${stateDir}/plugin-runtime-deps` before startup.

Low-level helpers still exist for downstream composition:

```nix
openclaw-nixos.lib.withBundledRuntimeDeps {
  package = openclaw-nixos.packages.${pkgs.system}.openclaw-gateway;
  pluginIds = [ "telegram" ];
}
```

and:

```nix
openclaw-nixos.lib.mkBundledPluginsPackage {
  inherit pkgs;
  package = openclaw-nixos.packages.${pkgs.system}.openclaw-gateway;
  pluginIds = [ "telegram" ];
}
```

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

OpenClaw configuration as a Nix attrset. Merged with generated plugin config and `configFile` if both are set (attrset wins on conflicts). Written to `/var/lib/openclaw/openclaw.json` by the setup service.

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

### `services.openclaw.plugins`
Type: `submodule`, Default: `{}`

Declarative plugin structure merged under top-level `plugins`.

- `allow`: plugin IDs appended to `plugins.allow`
- `slots`: slot assignments merged into `plugins.slots`
- `entries`: entry definitions merged into `plugins.entries`
- `installs`: install metadata merged into `plugins.installs`

```nix
services.openclaw.plugins = {
  slots.memory = "memory-cognee";
  entries.memory-cognee = {
    enabled = true;
    config.baseUrl = "http://127.0.0.1:8001";
  };
};
```

### `services.openclaw.bundledPlugins`
Type: `attrsOf submodule`, Default: `{}`

Declarative bundled plugin definitions keyed by upstream plugin ID.

- `enable`: adds the plugin ID to `plugins.allow`
- `config`: merged into `plugins.entries.<id>.config`
- `entry`: extra fields merged into `plugins.entries.<id>`
- `stageRuntimeDeps`: wraps the package and prepares an external stage tree so this bundled plugin's runtime deps are available without runtime installs

```nix
services.openclaw.bundledPlugins.telegram = {
  enable = true;
  stageRuntimeDeps = true;
  config.botToken = "BOT_TOKEN";
};
```

When `stageRuntimeDeps = true`, the module automatically wraps the configured package so that bundled plugin runtime deps are prepared during the build, copied into a live stage root during setup, and exposed to the service through `OPENCLAW_PLUGIN_STAGE_DIR`.

### `services.openclaw.localPlugins`
Type: `attrsOf submodule`, Default: `{}`

Declarative local packaged plugins keyed by plugin ID.

- `package`: packaged local plugin tree, typically built via `openclaw-nixos.lib.mkPluginPackage`
- `allow`: add the plugin ID to `plugins.allow` automatically
- `config`: merged into `plugins.entries.<id>.config`
- `entry`: extra fields merged into `plugins.entries.<id>`
- `install`: extra fields merged into `plugins.installs.<id>`
- `version`: rendered into `plugins.installs.<id>.version` when set, otherwise derived from the package version when available

Enabled local plugins are copied into a module-managed `${stateDir}/extensions/<pluginId>` tree and matched with generated `plugins.installs.<pluginId>` config.

If a local plugin declares runtime `dependencies`, the package must already vendor them. The module asserts this via `package.passthru.openclaw.requiresRuntimeDeps` and `hasVendoredRuntimeDeps`.

```nix
let
  memoryCognee =
    openclaw-nixos.lib.mkPluginPackage {
      inherit pkgs;
      pluginId = "memory-cognee";
      version = "2026.2.4";
      src = ./openclaw-plugins/memory-cognee;
    };
in {
  services.openclaw.localPlugins.memory-cognee = {
    package = memoryCognee;
    config.baseUrl = "http://127.0.0.1:8001";
  };

  services.openclaw.plugins.slots.memory = "memory-cognee";
}
```

To vendor runtime deps directly in the packaged plugin:

```nix
openclaw-nixos.lib.mkPluginPackage {
  inherit pkgs;
  pluginId = "memory-cognee";
  src = ./openclaw-plugins/memory-cognee;
  runtimeDeps.npm = {
    npmDepsHash = "sha256-...";
  };
}
```

To split dependency vendoring from plugin assembly:

```nix
let
  runtimeDeps =
    openclaw-nixos.lib.mkPluginRuntimeDepsFromNpmLock {
      inherit pkgs;
      pluginId = "memory-cognee";
      src = ./openclaw-plugins/memory-cognee;
      npmDepsHash = "sha256-...";
    };
in
openclaw-nixos.lib.mkPluginPackage {
  inherit pkgs;
  pluginId = "memory-cognee";
  src = ./openclaw-plugins/memory-cognee;
  runtimeDepsPackage = runtimeDeps;
}
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

When enabled, the adapter copies the packaged `dist/` tree into writable state and replaces `dist/extensions` with the filtered bundled plugin set there.

When disabled, the service points `OPENCLAW_BUNDLED_PLUGINS_DIR` directly at the filtered bundled-plugin artifact in the Nix store.

This is primarily a compatibility switch for hosts that need a writable bundled-plugin tree. The filtered bundled-plugin model works in both modes.

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

`userService` exposes the same `plugins`, `bundledPlugins`, and `localPlugins` options under `services.openclawUser`.

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
