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
    Normalize one `after` entry for single-effect jobs:
    - string `"job"` → `[ "job" "default" ]`
    - list (full attr path) left as-is
  */
  normalizeAfterEntry =
    entry:
    if builtins.isString entry then
      [
        entry
        "default"
      ]
    else if builtins.isList entry then
      entry
    else
      throw ''
        hci-effects: `after` entries must be a job name (string) or an
        attribute path (list of strings), e.g. `"deploy"` or [ "deploy" "default" ].
      '';

  normalizeAfter = after: map normalizeAfterEntry after;

  /*
    Rewrite `passthru.after` (and a top-level `after` when present) so short
    job-name deps become full `[ job "default" ]` paths.
  */
  withNormalizedAfter =
    effect:
    let
      raw =
        if effect ? passthru && effect.passthru ? after then
          effect.passthru.after
        else
          effect.after or [ ];
      normalized = normalizeAfter raw;
      passthru = (effect.passthru or { }) // {
        after = normalized;
      };
    in
    if normalized == raw then
      effect
    else if effect ? overrideAttrs then
      effect.overrideAttrs (_old: {
        inherit passthru;
      })
    else
      effect
      // {
        after = normalized;
        inherit passthru;
      };

  /*
    Transform resolved jobs into `herculesCI` `onPush` / `onSchedule` attrs.

    `on.push` must already be collapsed to `null` | `bool` (see
    `onPush.resolvePush`). Jobs with `on.push == null` are omitted from
    `onPush`; jobs with `on.schedule == null` are omitted from `onSchedule`.

    Each job exposes a single effect at `outputs.effects.default`.
  */
  mkOutputs =
    jobs:
    {
      onPush = lib.mapAttrs (_: job: {
        outputs.effects.default = runIf job.on.push (withNormalizedAfter job.effect);
      }) (lib.filterAttrs (_: job: job.on.push != null) jobs);

      onSchedule = lib.mapAttrs (_: job: {
        when = job.on.schedule;
        outputs.effects.default = withNormalizedAfter job.effect;
      }) (lib.filterAttrs (_: job: job.on.schedule != null) jobs);
    };
in
{
  inherit
    runIf
    mkOutputs
    normalizeAfter
    normalizeAfterEntry
    withNormalizedAfter
    ;
}
