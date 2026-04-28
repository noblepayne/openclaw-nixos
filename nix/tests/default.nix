{
  nixpkgs,
  system,
  openclawLib,
  openclaw-gateway,
  systemServiceModule,
  userServiceModule,
}: let
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

  selectedPluginIds = ["memory-core"];
  selectedBundledPlugins = openclawLib.mkBundledPluginsPackage {
    inherit pkgs;
    package = openclaw-gateway;
    pluginIds = selectedPluginIds;
  };
in {
  vm-system-service = pkgs.testers.runNixOSTest (
    {...}: {
      name = "openclaw-system-service";

      nodes.machine = {pkgs, ...}: {
        imports = [systemServiceModule];

        system.stateVersion = "26.05";
        environment.systemPackages = [
          pkgs.curl
          pkgs.jq
        ];

        services.openclaw = {
          enable = true;
          mutableExtensionsDir = false;
          port = 18789;
          bundledPlugins.memory-core = {
            enable = true;
          };
          localPlugins.fixture-with-runtime-deps.package = vendoredRuntimeDepsPlugin;
          plugins.slots.memory = "fixture-with-runtime-deps";
          config.gateway = {
            mode = "local";
            auth.token = "AUTH_TOKEN";
          };
        };
      };

      testScript = ''
        try:
            machine.wait_until_succeeds("systemctl is-active openclaw.service", timeout=180)
            machine.wait_until_succeeds("systemctl show openclaw-setup.service -p Result --value | grep -Fx success", timeout=60)
            machine.wait_until_succeeds("curl -fsS http://127.0.0.1:18789/health | jq -e '.ok == true'", timeout=60)
        except Exception:
            for command in (
                "systemctl status openclaw-setup.service --no-pager || true",
                "systemctl status openclaw.service --no-pager || true",
                "journalctl -u openclaw-setup.service -u openclaw.service --no-pager || true",
            ):
                _, out = machine.execute(command)
                print(out)
            raise

        machine.succeed("test -f /var/lib/openclaw/openclaw.json")
        machine.succeed("test -f /var/lib/openclaw/extensions/fixture-with-runtime-deps/openclaw.plugin.json")
        machine.succeed("test -f /var/lib/openclaw/extensions/fixture-with-runtime-deps/node_modules/left-pad/package.json")

        machine.succeed("systemctl show openclaw.service -p Environment --value | tr ' ' '\\n' | grep -Fx 'OPENCLAW_BUNDLED_PLUGINS_DIR=${selectedBundledPlugins}/dist/extensions'")
        machine.succeed("test -d ${selectedBundledPlugins}/dist/extensions/memory-core")
        machine.fail("test -e ${selectedBundledPlugins}/dist/extensions/googlechat")
      '';
    }
  );

  vm-user-service = pkgs.testers.runNixOSTest (
    {...}: {
      name = "openclaw-user-service";

      nodes.machine = {pkgs, ...}: {
        imports = [userServiceModule];

        system.stateVersion = "26.05";
        environment.systemPackages = [
          pkgs.curl
          pkgs.jq
        ];

        users.users.alice = {
          isNormalUser = true;
          home = "/home/alice";
          group = "users";
        };

        services.openclawUser = {
          enable = true;
          user = "alice";
          mutableExtensionsDir = false;
          port = 18789;
          bundledPlugins.memory-core = {
            enable = true;
          };
          localPlugins.fixture-no-runtime-deps.package = noRuntimeDepsPlugin;
          plugins.slots.memory = "fixture-no-runtime-deps";
          config.gateway = {
            mode = "local";
            auth.token = "AUTH_TOKEN";
          };
        };
      };

      testScript = ''
        machine.succeed("loginctl enable-linger alice")
        machine.wait_for_unit("user@1000.service")
        try:
            machine.wait_until_succeeds("systemctl --user --machine=alice@ is-active openclaw.service", timeout=180)
            machine.wait_until_succeeds("curl -fsS http://127.0.0.1:18789/health | jq -e '.ok == true'", timeout=60)
        except Exception:
            for command in (
                "systemctl --user --machine=alice@ status openclaw.service --no-pager || true",
                "journalctl --user --user-unit=openclaw.service --machine=alice@ --no-pager || true",
            ):
                _, out = machine.execute(command)
                print(out)
            raise

        machine.succeed("test -f /home/alice/.local/share/openclaw/openclaw.json")
        machine.succeed("test -f /home/alice/.local/share/openclaw/extensions/fixture-no-runtime-deps/openclaw.plugin.json")

        machine.succeed("systemctl --user --machine=alice@ show openclaw.service -p Environment --value | tr ' ' '\\n' | grep -Fx 'OPENCLAW_BUNDLED_PLUGINS_DIR=${selectedBundledPlugins}/dist/extensions'")
        machine.fail("test -e ${selectedBundledPlugins}/dist/extensions/googlechat")
      '';
    }
  );
}
