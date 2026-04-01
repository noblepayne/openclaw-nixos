# openclaw-nixos

NixOS module and package for [OpenClaw](https://github.com/openclaw/openclaw).

Linux x86_64 only. No home-manager, no darwin, no plugin catalog. Just a gateway build and a systemd service.

## Usage

```nix
# flake.nix
{
  inputs.openclaw-nixos.url = "github:YOUR_ORG/openclaw-nixos";

  outputs = { nixpkgs, openclaw-nixos, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        openclaw-nixos.nixosModules.default
        {
          services.openclaw = {
            enable = true;
            port = 3000;
            config = {
              channels.telegram.token = "BOT_TOKEN";
              gateway.auth.token = "AUTH_TOKEN";
            };
          };
        }
      ];
    };
  };
}
```

## Module options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `services.openclaw.enable` | bool | false | Enable OpenClaw gateway |
| `services.openclaw.package` | package | `pkgs.openclaw-gateway` | Gateway package |
| `services.openclaw.port` | port | 3000 | Bind port |
| `services.openclaw.bind` | str | "127.0.0.1" | Bind address |
| `services.openclaw.config` | attrs | {} | OpenClaw config (merged with configFile) |
| `services.openclaw.configFile` | path | null | Path to openclaw.json |
| `services.openclaw.openFirewall` | bool | false | Open firewall for port |
| `services.openclaw.user` | str | "openclaw" | System user |
| `services.openclaw.group` | str | "openclaw" | System group |

## Updating the upstream pin

```bash
scripts/update-pin.sh
```

## Lockfile pruner

The build uses a pruned pnpm lockfile that strips platform-specific binaries for non-linux targets. See [docs/lockfile-pruner.md](docs/lockfile-pruner.md).

## Documentation

- [Architecture](docs/architecture.md) — how it all fits together
- [Pinning](docs/pinning.md) — how pins and updates work
- [Build](docs/build.md) — how the Nix build works
- [Module](docs/module.md) — NixOS module reference
- [Lockfile Pruner](docs/lockfile-pruner.md) — platform-specific dependency pruning

## License

MIT

Build infrastructure adapted from [nix-openclaw](https://github.com/nix-openclaw/nix-openclaw) ([Unlicense](https://github.com/nix-openclaw/nix-openclaw/blob/main/LICENSE)).
