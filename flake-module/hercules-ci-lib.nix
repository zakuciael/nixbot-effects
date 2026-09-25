# Pure helpers used to build `flake.herculesCI` from resolved jobs.
{ lib }:
let
  /*
    Wrap an effect so Hercules CI either runs it (`condition == true`) or
    only builds its dependencies (`condition == false`).
  */
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

  /*
    Transform resolved jobs into `herculesCI` `onPush` / `onSchedule` attrs.

    `on.push` must already be collapsed to `null` | `bool` (see
    `onPush.resolvePush`). Jobs with `on.push == null` are omitted from
    `onPush`; jobs with `on.schedule == null` are omitted from `onSchedule`.
  */
  mkOutputs =
    jobs:
    {
      onPush = lib.mapAttrs (_: job: {
        outputs.effects = lib.mapAttrs (_: effect: runIf job.on.push effect) job.steps;
      }) (lib.filterAttrs (_: job: job.on.push != null) jobs);

      onSchedule = lib.mapAttrs (_: job: {
        when = job.on.schedule;
        outputs.effects = job.steps;
      }) (lib.filterAttrs (_: job: job.on.schedule != null) jobs);
    };
in
{
  inherit runIf mkOutputs;
}
