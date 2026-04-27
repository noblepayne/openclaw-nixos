{
  description = "NixOS module and package for OpenClaw (linux x86_64)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    openclaw = {
      url = "github:openclaw/openclaw/v2026.4.22";
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
    baseOpenclawLib = import ./nix/lib/default.nix {lib = nixpkgs.lib;};
    openclawLib =
      baseOpenclawLib
      // {
        mkPluginPackage =
          {
            pkgs,
            ...
          }@args:
          pkgs.callPackage ./nix/packages/openclaw-plugin.nix (builtins.removeAttrs args [ "pkgs" ]);
      };

    # The pruned lockfile lives in our repo
    prunedLockfile = ./pnpm-lock-pruned.yaml;

    # pnpmDepsHash must be updated when the pruned lockfile changes.
    # Run: nix build .#openclaw-gateway 2>&1 | grep 'got:' to get the new hash
    # Or: scripts/update-pin.sh
    pnpmDepsHash = "sha256-bfZ5Rp26bHp9J+NClI+HtSSnPRojO8qUcJk0C8AqcwI=";

    openclaw-gateway = pkgs.callPackage ./nix/packages/openclaw-gateway.nix {
      inherit prunedLockfile pnpmDepsHash;
      openclawSrc = openclaw;
    };
    mkSystemModule = path: {
      pkgs,
      ...
    }: {
      _module.args.openclawSystemDefaultPackage = self.packages.${pkgs.system}.openclaw-gateway;
      imports = [ path ];
    };
    mkUserModule = path: {
      pkgs,
      ...
    }: {
      _module.args.openclawUserDefaultPackage = self.packages.${pkgs.system}.openclaw-gateway;
      imports = [ path ];
    };
  in {
    packages.${system} = {
      inherit openclaw-gateway;
      default = openclaw-gateway;
    };

    lib = openclawLib;

    nixosModules = {
      default = mkSystemModule ./nix/modules/openclaw.nix;
      systemService = mkSystemModule ./nix/modules/openclaw.nix;
      userService = mkUserModule ./nix/modules/openclaw-user.nix;
    };

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
