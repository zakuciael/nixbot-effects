{
  config,
  lib,
  ...
}:
let
  runIf =
    condition: effect:
    if condition then
      { run = effect; }
    else
      {
        dependencies = effect.inputDerivation // {
          isEffect = false;
          buildDependenciesOnly = true;
        };
      };
in
{
  config = {
    flake.herculesCI =
      {
        primaryRepo ? throw "`<flake>.outputs.herculesCI` requires a `primaryRepo` argument.",
        ...
      }:
      let
        jobs = config.hci-effects primaryRepo;
      in
      {
        onPush = lib.mapAttrs (_: job: {
          outputs.effects = lib.mapAttrs (_: effect: runIf job.on.push effect) job.steps;
        }) (lib.filterAttrs (_: job: job.on.push != null) jobs);

        onSchedule = lib.mapAttrs (_: job: {
          when = job.on.schedule;
          outputs.effects = job.steps;
        }) (lib.filterAttrs (_: job: job.on.schedule != null) jobs);
      };
  };
}
