{ lib }:
let
  readConfigFile =
    configFile:
    if configFile != null then
      builtins.fromJSON (builtins.readFile configFile)
    else
      { };

  mergeConfig =
    {
      configFile ? null,
      config ? { },
    }:
    lib.recursiveUpdate (readConfigFile configFile) config;

  renderConfigJson =
    {
      configFile ? null,
      config ? { },
    }:
    builtins.toJSON (mergeConfig {
      inherit configFile config;
    });

  renderCronJobsJson =
    {
      cronJobs ? { },
    }:
    builtins.toJSON cronJobs;

  mkConfigPath = stateDir: "${stateDir}/openclaw.json";
  mkCronDir = stateDir: "${stateDir}/cron";
  mkCronJobsPath = stateDir: "${mkCronDir stateDir}/jobs.json";
  mkDistDir = stateDir: "${stateDir}/dist";
  mkExtensionsDir = stateDir: "${mkDistDir stateDir}/extensions";
in
{
  inherit
    mergeConfig
    renderConfigJson
    renderCronJobsJson
    mkConfigPath
    mkCronDir
    mkCronJobsPath
    mkDistDir
    mkExtensionsDir
    ;
}
