# openclaw-nixos

A lean, NixOS-focused distribution of the [OpenClaw](https://github.com/openclaw/openclaw) AI agent gateway.

This flake provides a simplified, server-oriented build that strips away 18,000+ lines of desktop-specific complexity found in other distributions. It targets **Linux x86_64** exclusively, ensuring a predictable and efficient deployment for autonomous agent VMs.

## Key Features

- **Lean Build**: Focuses on the gateway and core runtime. No home-manager, no macOS cruft, no auto-generated 15k-line schema.
- **Smart Dependency Pruning**: Uses a custom lockfile pruner to strip ~200 platform-specific binaries (Windows, Android, etc.) reducing build overhead and store bloat.
- **NixOS Native**: Simple, robust NixOS module with hardening and state management based on real-world deployments.
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
        openclaw-nixos.nixosModules.default
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

## Documentation

- [Architecture](docs/architecture.md) — How the lean build is structured.
- [NixOS Module](docs/module.md) — Full reference for `services.openclaw` options.
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

Build infrastructure adapted from [nix-openclaw](https://github.com/nix-openclaw/nix-openclaw). Initial architecture inspired by [lattice](https://github.com/noblepayne/lattice).
