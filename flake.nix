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
      let
        self =
          baseOpenclawLib
          // {
        mkBundledRuntimeDepsPackage =
          {
            pkgs,
            ...
          }@args:
          pkgs.callPackage ./nix/packages/openclaw-bundled-runtime-deps.nix (builtins.removeAttrs args [ "pkgs" ]);
        mkPluginRuntimeDepsFromNpmLock =
          {
            pkgs,
            ...
          }@args:
          pkgs.callPackage ./nix/packages/openclaw-plugin-runtime-deps.nix (builtins.removeAttrs args [ "pkgs" ]);
        mkPluginPackage =
          {
            pkgs,
            runtimeDeps ? null,
            ...
          }@args:
          let
            resolvedRuntimeDepsPackage =
              if args ? runtimeDepsPackage then
                args.runtimeDepsPackage
              else if runtimeDeps != null && runtimeDeps ? npm then
                self.mkPluginRuntimeDepsFromNpmLock (
                  {
                    inherit pkgs;
                    inherit (args) src pluginId;
                    version = args.version or "0.0.0";
                  }
                  // runtimeDeps.npm
                )
              else
                null;
          in
          pkgs.callPackage ./nix/packages/openclaw-plugin.nix (
            (builtins.removeAttrs args [ "pkgs" "runtimeDeps" ])
            // {
              runtimeDepsPackage = resolvedRuntimeDepsPackage;
            }
          );
      };
      in
      self;

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
    openclaw-bundled-runtime-deps = openclawLib.mkBundledRuntimeDepsPackage {
      inherit pkgs;
      package = openclaw-gateway;
      pluginIds = [ ];
    };
    mkSystemModule = path: {
      pkgs,
      ...
    }: {
      _module.args.openclawSystemDefaultPackage =
        self.packages.${pkgs.stdenv.hostPlatform.system}.openclaw-gateway;
      imports = [ path ];
    };
    mkUserModule = path: {
      pkgs,
      ...
    }: {
      _module.args.openclawUserDefaultPackage =
        self.packages.${pkgs.stdenv.hostPlatform.system}.openclaw-gateway;
      imports = [ path ];
    };
    systemServiceModule = mkSystemModule ./nix/modules/openclaw.nix;
    userServiceModule = mkUserModule ./nix/modules/openclaw-user.nix;
    checks = import ./nix/checks/default.nix {
      inherit
        nixpkgs
        system
        openclawLib
        openclaw-gateway
        systemServiceModule
        userServiceModule
        ;
    };
  in {
    packages.${system} = {
      inherit openclaw-gateway openclaw-bundled-runtime-deps;
      default = openclaw-gateway;
    };

    checks.${system} = checks;

    lib = openclawLib;

    nixosModules = {
      default = systemServiceModule;
      systemService = systemServiceModule;
      userService = userServiceModule;
    };

    overlays.default = final: _prev: let
      drv = final.callPackage ./nix/packages/openclaw-gateway.nix {
        inherit prunedLockfile pnpmDepsHash;
        openclawSrc = openclaw;
      };
      runtimeDepsDrv = final.callPackage ./nix/packages/openclaw-bundled-runtime-deps.nix {
        package = drv;
        pluginIds = [ ];
      };
    in {
      openclaw-gateway = drv;
      openclaw-bundled-runtime-deps = runtimeDepsDrv;
      openclaw = drv;
    };
  };
}
