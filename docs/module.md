# NixOS Module

## Enabling

Add to your NixOS configuration:

```nix
{
  imports = [openclaw-nixos.nixosModules.default];

  services.openclaw = {
    enable = true;
    port = 3000;
    config = {
      channels.telegram.token = "BOT_TOKEN";
      gateway.auth.token = "AUTH_TOKEN";
      # ... any other openclaw config
    };
  };
}
```

Or if using as a flake overlay:

```nix
{
  # In your flake
  openclaw-nixos.overlays.default;

  services.openclaw = {
    enable = true;
    package = pkgs.openclaw-gateway;
    # ...
  };
}
```

## Configuration options

### `services.openclaw.enable`

Type: `bool`, Default: `false`

Enable the OpenClaw gateway service.

### `services.openclaw.package`

Type: `package`, Default: `pkgs.openclaw-gateway`

The OpenClaw gateway package to use. Override to use a custom build.

### `services.openclaw.port`

Type: `port`, Default: `3000`

Port for the gateway to listen on.

### `services.openclaw.bind`

Type: `string`, Default: `"127.0.0.1"`

Address to bind to. Use `"0.0.0.0"` for all interfaces.

### `services.openclaw.config`

Type: `attrs`, Default: `{}`

OpenClaw configuration as a Nix attrset. Written to `~/.openclaw/openclaw.json` in the service's home directory.

```nix
services.openclaw.config = {
  channels.telegram.token = "BOT_TOKEN";
  channels.telegram.enabled = true;
  gateway.auth.token = "AUTH_TOKEN";
  gateway.port = 3000;
  providers.openai.apiKey = "sk-...";
  memory.enabled = true;
};
```

### `services.openclaw.configFile`

Type: `path`, Default: `null`

Path to an existing `openclaw.json` file. If both `config` and `configFile` are set, the attrset is merged on top of the file contents (attrset wins on conflicts).

```nix
services.openclaw.configFile = ./my-openclaw.json;
```

### `services.openclaw.openFirewall`

Type: `bool`, Default: `false`

Open the firewall for the configured port.

### `services.openclaw.user`

Type: `string`, Default: `"openclaw"`

System user to run the service as. Created automatically as a system user.

### `services.openclaw.group`

Type: `string`, Default: `"openclaw"`

System group for the service user.

## What the module creates

When enabled, the module sets up:

1. **User/group**: `openclaw:openclaw` (system user, no login shell)
2. **State directory**: `/var/lib/openclaw` (owned by service user)
3. **Config file**: `/var/lib/openclaw/.openclaw/openclaw.json` (mode 600)
4. **Systemd service**: `openclaw.service`
   - `Restart=always`, `RestartSec=5`
   - Hardened: `NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome`, `PrivateTmp`
5. **Firewall**: TCP port opened if `openFirewall = true`

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
  };
}
```

## Troubleshooting

### Service won't start

```bash
journalctl -u openclaw -f
```

Check for:
- Missing config (no `config` or `configFile` set)
- Permission issues on `/var/lib/openclaw`
- Port conflicts

### Config not being read

The config is written to `/var/lib/openclaw/.openclaw/openclaw.json` in `preStart`. Check:
- File exists and has correct content
- File permissions are 600
- Service user can read it

### State got corrupted

```bash
systemctl stop openclaw
rm -rf /var/lib/openclaw/.openclaw
systemctl start openclaw
```
