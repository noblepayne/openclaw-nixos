# openclaw-nixos

A lean, NixOS-focused distribution of the [OpenClaw](https://github.com/openclaw/openclaw) AI agent gateway.

This flake provides a simplified, server-oriented build that strips away 18,000+ lines of desktop-specific complexity found in other distributions. It targets **Linux x86_64** exclusively, while exposing composable Nix pieces that downstream hosts can combine into either a system-level service or a user-level service.

## Key Features

- **Lean Build**: Focuses on the gateway and core runtime. No home-manager, no macOS cruft, no auto-generated 15k-line schema.
- **Smart Dependency Pruning**: Uses a custom lockfile pruner to strip ~200 platform-specific binaries (Windows, Android, etc.) reducing build overhead and store bloat.
- **Composable Surface**: Exposes a package, shared rendering library, and both system-service and user-service NixOS modules.
- **Build-Time Runtime Deps**: Can selectively stage bundled plugin runtime dependencies during the package build, so chosen packaged plugins avoid npm installs at service startup.
- **NixOS Native**: Simple, robust system-service module with hardening and state management based on real-world deployments.
- **Deterministic**: Standardized build flow with verified pnpm dependency integrity.

## Quick Start

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
              # Configuration via Nix attrsets
              gateway.cors.origins = [ "https://dashboard.example.com" ];
              memory.enabled = true;
            };
            
            # Use configFile for pre-existing JSON
            # configFile = "/var/lib/openclaw/credentials/openclaw.json";
            
            openFirewall = true;
          };
        }
      ];
    };
  };
}
```

## Handling Secrets

Sensitive credentials (API keys, bot tokens) should **not** be placed in the Nix `config` attrset as they will be world-readable in the Nix store. 

Recommended approaches:
1.  **`EnvironmentFile`**: Define secrets in a file on the host and reference it (managed via the systemd service).
2.  **`configFile`**: Point the module to a JSON file with restricted permissions already present on the server.
3.  **Merged Config**: Use both! The Nix module will merge your `config` attrset on top of your `configFile`, allowing you to keep structure in Nix and secrets in a private file.

The system adapter uses `services.openclaw`. The user-service adapter uses `services.openclawUser`.

To pre-stage bundled plugin runtime deps for a selected plugin set, override the package. The default remains conservative: no bundled plugin runtime deps are staged unless you opt a plugin in.

```nix
{
  services.openclaw.package =
    openclaw-nixos.lib.withBundledRuntimeDeps {
      package = openclaw-nixos.packages.${pkgs.system}.openclaw-gateway;
      pluginIds = [ "telegram" ];
    };
}
```

Set `preserveUpstream = true;` if you need to preserve upstream's staged-plugin set instead of selecting an explicit subset.

## Documentation

- [Architecture](docs/architecture.md) — How the lean build is structured.
- [NixOS Module](docs/module.md) — Full reference for `services.openclaw` and `services.openclawUser`.
- [Nix Build](docs/build.md) — Deep dive into the pnpm-to-Nix pipeline.
- [Pinning & Updates](docs/pinning.md) — Instructions for bumping upstream versions.
- [Lockfile Pruner](docs/lockfile-pruner.md) — How we strip non-linux binaries.

## Maintenance

To update the upstream OpenClaw pin and refresh the pruned lockfile:

```bash
# Pulls new SHA and runs the pruner
./scripts/update-pin.sh
```

## Credits & License

MIT License.

Build infrastructure adapted from [nix-openclaw](https://github.com/nix-openclaw/nix-openclaw).
