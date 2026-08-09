{
  config,
  lib,
  ...
}:
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
          outputs.effects = lib.mapAttrs (
            _: step:
            if job.on.push then
              { run = step; }
            else
              {
                dependencies = step.inputDerivation // {
                  isEffect = false;
                  buildDependenciesOnly = true;
                };
              }
          ) job.steps;
        }) (lib.filterAttrs (_: job: job.on.push != null) jobs);

        onSchedule = lib.mapAttrs (_: job: {
          when = job.on.schedule;
          outputs.effects = job.steps;
        }) (lib.filterAttrs (_: job: job.on.schedule != null) jobs);
      };
  };
}
