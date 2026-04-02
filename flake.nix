{
  description = "NixOS module and package for OpenClaw (linux x86_64)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    openclaw = {
      url = "github:openclaw/openclaw/v2026.4.2";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    openclaw,
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};

    # The pruned lockfile lives in our repo
    prunedLockfile = ./pnpm-lock-pruned.yaml;

    # pnpmDepsHash must be updated when the pruned lockfile changes.
    # Run: nix build .#openclaw-gateway 2>&1 | grep 'got:' to get the new hash
    # Or: scripts/update-pin.sh
    pnpmDepsHash = "sha256-cg0A7iNpH4LijEI/DZgjoHxlY5vrx7bcnV8oBrxJ3sc=";

    openclaw-gateway = pkgs.callPackage ./nix/packages/openclaw-gateway.nix {
      inherit prunedLockfile pnpmDepsHash;
      openclawSrc = openclaw;
    };
  in {
    packages.${system} = {
      inherit openclaw-gateway;
      default = openclaw-gateway;
    };

    nixosModules.default = ./nix/modules/openclaw.nix;

    overlays.default = final: _prev: let
      drv = final.callPackage ./nix/packages/openclaw-gateway.nix {
        inherit prunedLockfile pnpmDepsHash;
        openclawSrc = openclaw;
      };
    in {
      openclaw-gateway = drv;
      openclaw = drv;
    };
  };
}
