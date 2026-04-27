{
  nixpkgs,
  system,
  openclawLib,
  openclaw-gateway,
  systemServiceModule,
  userServiceModule,
}:
let
  lib = nixpkgs.lib;
  pkgs = nixpkgs.legacyPackages.${system};

  fixtureNoRuntimeDeps = ../../tests/fixtures/plugins/no-runtime-deps;
  fixtureWithRuntimeDeps = ../../tests/fixtures/plugins/with-runtime-deps;
  fixtureWithRuntimeDepsHash = "sha256-LI7tTlobSg+DWH1H21OY+DWbl6qhG+4paueSJ7FxowQ=";

  noRuntimeDepsPlugin = openclawLib.mkPluginPackage {
    inherit pkgs;
    pluginId = "fixture-no-runtime-deps";
    src = fixtureNoRuntimeDeps;
    version = "1.0.0";
  };

  runtimeDepsOnly = openclawLib.mkPluginRuntimeDepsFromNpmLock {
    inherit pkgs;
    pluginId = "fixture-with-runtime-deps";
    src = fixtureWithRuntimeDeps;
    version = "1.0.0";
    npmDepsHash = fixtureWithRuntimeDepsHash;
  };

  vendoredRuntimeDepsPlugin = openclawLib.mkPluginPackage {
    inherit pkgs;
    pluginId = "fixture-with-runtime-deps";
    src = fixtureWithRuntimeDeps;
    version = "1.0.0";
    runtimeDeps = {
      npm = {
        npmDepsHash = fixtureWithRuntimeDepsHash;
      };
    };
  };

  renderedPluginsConfig = openclawLib.renderPluginsConfig {
    stateDir = "/var/lib/openclaw";
    bundledPlugins.telegram = {
      enable = true;
      config.token = "TOKEN";
      entry.channel = "telegram";
      stageRuntimeDeps = true;
    };
    localPlugins.fixture-with-runtime-deps = {
      package = vendoredRuntimeDepsPlugin;
      version = "1.0.0";
      config.mode = "memory";
      entry.kind = "local";
    };
    plugins = {
      allow = [ "manual-plugin" ];
      slots.memory = "fixture-with-runtime-deps";
    };
  };

  selectedBundledGateway = openclawLib.withBundledRuntimeDeps {
    package = openclaw-gateway;
    pluginIds = [ "telegram" ];
  };
  selectedBundledPlugins = openclawLib.mkBundledPluginsPackage {
    inherit pkgs;
    package = selectedBundledGateway;
    pluginIds = [ "telegram" ];
  };
  selectedBundledRuntimeDeps = openclawLib.mkBundledRuntimeDepsPackage {
    inherit pkgs;
    package = selectedBundledGateway;
    pluginIds = [ "telegram" ];
  };

  systemModuleEval =
    nixpkgs.lib.nixosSystem {
      modules = [
        {
          nixpkgs.hostPlatform = system;
          system.stateVersion = "26.05";
        }
        systemServiceModule
        (
          { ... }:
          {
            services.openclaw = {
              enable = true;
              port = 4100;
              bundledPlugins.telegram = {
                enable = true;
                stageRuntimeDeps = true;
                config.token = "TOKEN";
              };
              localPlugins.fixture-with-runtime-deps = {
                package = vendoredRuntimeDepsPlugin;
                config.mode = "capture";
              };
              plugins.slots.memory = "fixture-with-runtime-deps";
              config.gateway.auth.token = "AUTH_TOKEN";
            };
          }
        )
      ];
    };

  userModuleEval =
    nixpkgs.lib.nixosSystem {
      modules = [
        {
          nixpkgs.hostPlatform = system;
          system.stateVersion = "26.05";
        }
        userServiceModule
        (
          { ... }:
          {
            users.users.chris = {
              isNormalUser = true;
              home = "/home/chris";
              group = "users";
            };

            services.openclawUser = {
              enable = true;
              user = "chris";
              port = 4200;
              bundledPlugins.telegram = {
                enable = true;
                stageRuntimeDeps = true;
                config.token = "TOKEN";
              };
              localPlugins.fixture-no-runtime-deps = {
                package = noRuntimeDepsPlugin;
                config.mode = "recall";
              };
              plugins.slots.memory = "fixture-no-runtime-deps";
              config.gateway.auth.token = "AUTH_TOKEN";
            };
          }
        )
      ];
    };

  invalidSystemStateEval = builtins.tryEval (
    let
      broken =
        nixpkgs.lib.nixosSystem {
          modules = [
            {
              nixpkgs.hostPlatform = system;
              system.stateVersion = "26.05";
            }
            systemServiceModule
            (
              { ... }:
              {
                services.openclaw = {
                  enable = true;
                  stateDir = "/home/openclaw";
                };
              }
            )
          ];
        };
    in
    broken.config.system.build.toplevel.drvPath
  );

  invalidUserEval = builtins.tryEval (
    let
      broken =
        nixpkgs.lib.nixosSystem {
          modules = [
            {
              nixpkgs.hostPlatform = system;
              system.stateVersion = "26.05";
            }
            userServiceModule
            (
              { ... }:
              {
                services.openclawUser.enable = true;
              }
            )
          ];
        };
    in
    broken.config.system.build.toplevel.drvPath
  );

  missingVendoredDepsEval = builtins.tryEval (
    openclawLib.mkPluginPackage {
      inherit pkgs;
      pluginId = "fixture-with-runtime-deps";
      src = fixtureWithRuntimeDeps;
      version = "1.0.0";
    }
  );

  mismatchedPluginIdEval = builtins.tryEval (
    openclawLib.mkPluginPackage {
      inherit pkgs;
      pluginId = "wrong-plugin-id";
      src = fixtureNoRuntimeDeps;
      version = "1.0.0";
    }
  );

  syntaxCheck = pkgs.runCommand "openclaw-script-syntax-check" {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.nodejs
    ];
  } ''
    bash -n ${../../scripts/roll-update.sh}
    bash -n ${../../scripts/update-pin.sh}
    node --check ${../../nix/scripts/stage-bundled-plugin-runtime-deps-wrapper.mjs}
    touch "$out"
  '';

  systemSetupScript = systemModuleEval.config.systemd.services.openclaw-setup.script;
  systemEnvironment = systemModuleEval.config.systemd.services.openclaw.environment;
  userActivationScript = userModuleEval.config.system.activationScripts."openclaw-user-setup-chris".text;
  userEnvironment = userModuleEval.config.systemd.user.services.openclaw.environment;
in
{
  lib-render-plugins =
    assert renderedPluginsConfig.plugins.allow == [
      "manual-plugin"
      "telegram"
      "fixture-with-runtime-deps"
    ];
    assert renderedPluginsConfig.plugins.slots.memory == "fixture-with-runtime-deps";
    assert renderedPluginsConfig.plugins.entries.telegram.config.token == "TOKEN";
    assert renderedPluginsConfig.plugins.entries.telegram.channel == "telegram";
    assert renderedPluginsConfig.plugins.entries.fixture-with-runtime-deps.kind == "local";
    assert renderedPluginsConfig.plugins.installs.fixture-with-runtime-deps.installPath
      == "/var/lib/openclaw/extensions/fixture-with-runtime-deps";
    assert renderedPluginsConfig.plugins.installs.fixture-with-runtime-deps.sourcePath
      == toString vendoredRuntimeDepsPlugin;
    assert openclawLib.bundledRuntimeDepsPluginIds {
      telegram = {
        enable = true;
        stageRuntimeDeps = true;
      };
      discord = {
        enable = true;
        stageRuntimeDeps = false;
      };
      browser = {
        enable = true;
        stageRuntimeDeps = true;
      };
    } == [
      "browser"
      "telegram"
    ];
    pkgs.runCommand "openclaw-lib-render-plugins-check" { } "touch $out";

  local-plugin-package-basic = pkgs.runCommand "openclaw-local-plugin-basic-check" {
    nativeBuildInputs = [ pkgs.jq ];
  } ''
    test -f ${noRuntimeDepsPlugin}/openclaw.plugin.json
    test -f ${noRuntimeDepsPlugin}/package.json
    test -f ${noRuntimeDepsPlugin}/dist/index.js
    test ! -e ${noRuntimeDepsPlugin}/.git
    test ! -e ${noRuntimeDepsPlugin}/.github
    test "$(${pkgs.jq}/bin/jq -r '.id' ${noRuntimeDepsPlugin}/openclaw.plugin.json)" = "fixture-no-runtime-deps"
    touch "$out"
  '';

  local-plugin-runtime-deps-helper = pkgs.runCommand "openclaw-local-plugin-runtime-deps-helper-check" { } ''
    test -d ${runtimeDepsOnly}/node_modules/left-pad
    test -f ${runtimeDepsOnly}/node_modules/left-pad/package.json
    touch "$out"
  '';

  local-plugin-package-runtime-deps = pkgs.runCommand "openclaw-local-plugin-runtime-deps-check" {
    nativeBuildInputs = [ pkgs.jq ];
  } ''
    test -d ${vendoredRuntimeDepsPlugin}/node_modules/left-pad
    test -f ${vendoredRuntimeDepsPlugin}/node_modules/left-pad/package.json
    test ! -f ${vendoredRuntimeDepsPlugin}/package-lock.json
    test "$(${pkgs.jq}/bin/jq 'has("dependencies")' ${vendoredRuntimeDepsPlugin}/package.json)" = "false"
    touch "$out"
  '';

  module-eval-system-service =
    assert systemModuleEval.config.systemd.services.openclaw.serviceConfig.ExecStart
      == "${selectedBundledGateway}/bin/openclaw gateway";
    assert systemEnvironment.OPENCLAW_CONFIG_PATH == "/var/lib/openclaw/openclaw.json";
    assert systemEnvironment.OPENCLAW_BUNDLED_PLUGINS_DIR == "/var/lib/openclaw/dist/extensions";
    assert systemEnvironment.OPENCLAW_PLUGIN_STAGE_DIR == "/var/lib/openclaw/plugin-runtime-deps";
    assert builtins.hasAttr "CONFIG_HASH" systemEnvironment;
    assert systemModuleEval.config.users.users.openclaw.isSystemUser;
    assert systemModuleEval.config.users.groups ? openclaw;
    assert lib.hasInfix "fixture-with-runtime-deps" systemSetupScript;
    assert lib.hasInfix "plugin-runtime-deps" systemSetupScript;
    assert lib.hasInfix "/dist" systemSetupScript;
    assert lib.hasInfix "node_modules/openclaw" systemSetupScript;
    assert lib.hasInfix "/var/lib/openclaw/extensions/fixture-with-runtime-deps" systemSetupScript;
    pkgs.runCommand "openclaw-module-eval-system-service-check" { } "touch $out";

  module-eval-user-service =
    assert userModuleEval.config.systemd.user.services.openclaw.unitConfig.ConditionUser == "chris";
    assert userModuleEval.config.systemd.user.services.openclaw.serviceConfig.WorkingDirectory
      == "/home/chris/.local/share/openclaw";
    assert userEnvironment.HOME == "/home/chris";
    assert userEnvironment.OPENCLAW_CONFIG_PATH == "/home/chris/.local/share/openclaw/openclaw.json";
    assert userEnvironment.OPENCLAW_BUNDLED_PLUGINS_DIR == "/home/chris/.local/share/openclaw/dist/extensions";
    assert userEnvironment.OPENCLAW_PLUGIN_STAGE_DIR == "/home/chris/.local/share/openclaw/plugin-runtime-deps";
    assert userModuleEval.config.users.users.chris.linger;
    assert lib.hasInfix "fixture-no-runtime-deps" userActivationScript;
    assert lib.hasInfix "plugin-runtime-deps" userActivationScript;
    assert lib.hasInfix "/dist" userActivationScript;
    assert lib.hasInfix "node_modules/openclaw" userActivationScript;
    assert lib.hasInfix "/home/chris/.local/share/openclaw/extensions/fixture-no-runtime-deps" userActivationScript;
    pkgs.runCommand "openclaw-module-eval-user-service-check" { } "touch $out";

  module-negative-assertions =
    assert !invalidSystemStateEval.success;
    assert !invalidUserEval.success;
    assert !missingVendoredDepsEval.success;
    assert !mismatchedPluginIdEval.success;
    pkgs.runCommand "openclaw-module-negative-assertions-check" { } "touch $out";

  bundled-runtime-deps-default-build = pkgs.runCommand "openclaw-bundled-runtime-deps-default-check" { } ''
    test ! -e ${openclaw-gateway}/lib/openclaw/dist/extensions/telegram/node_modules
    touch "$out"
  '';

  bundled-plugins-package = pkgs.runCommand "openclaw-bundled-plugins-package-check" { } ''
    test -f ${selectedBundledPlugins}/package.json
    test -d ${selectedBundledPlugins}/dist
    test -d ${selectedBundledPlugins}/dist/extensions/telegram
    test -d ${selectedBundledPlugins}/dist/extensions/node_modules/openclaw
    test -f ${selectedBundledPlugins}/dist/plugin-sdk/channel-entry-contract.js
    test ! -e ${selectedBundledPlugins}/dist/extensions/googlechat
    touch "$out"
  '';

  bundled-runtime-deps-selected-build = pkgs.runCommand "openclaw-bundled-runtime-deps-selected-check" { } ''
    test -d ${selectedBundledGateway}/lib/openclaw/dist/extensions/telegram/node_modules
    touch "$out"
  '';

  bundled-runtime-deps-package = pkgs.runCommand "openclaw-bundled-runtime-deps-package-check" { } ''
    test -f ${selectedBundledRuntimeDeps}/.openclaw-package-key
    package_key="$(cat ${selectedBundledRuntimeDeps}/.openclaw-package-key)"
    test -n "$package_key"
    test -d ${selectedBundledRuntimeDeps}/"$package_key"
    test -d ${selectedBundledRuntimeDeps}/"$package_key"/node_modules
    test ! -L ${selectedBundledRuntimeDeps}/"$package_key"/node_modules
    test ! -e ${selectedBundledRuntimeDeps}/"$package_key"/dist
    test ! -e ${selectedBundledRuntimeDeps}/"$package_key"/node_modules/openclaw
    test -f ${selectedBundledRuntimeDeps}/.openclaw-selected-plugin-ids.json
    touch "$out"
  '';

  script-syntax = syntaxCheck;
}
