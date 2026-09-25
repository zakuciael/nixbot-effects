# Pure helpers used to build `flake.herculesCI` from resolved jobs.
{ lib }:
let
  onEvent = import ./types/on-event.nix { inherit lib; };
  inherit (onEvent) eventKinds whenFromOption;

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

  effectAfter =
    effect:
    if effect ? passthru && effect.passthru ? after then
      effect.passthru.after
    else
      effect.after or [ ];

  effectWhen =
    effect:
    if effect ? passthru && effect.passthru ? when then
      effect.passthru.when
    else
      effect.when or { };

  /*
    Rewrite `passthru.after` (and a top-level `after` when present) so short
    job-name deps become full `[ job "default" ]` paths.
  */
  withNormalizedAfter =
    effect:
    let
      raw = effectAfter effect;
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
    Attach `when` for an onEvent effect. Rejects non-empty `mkEffect.when` or
    `after` — event jobs own conditions via `on.<event>`, and nixbot ignores
    `after` on event effects.
  */
  withEventWhen =
    jobName: kind: when: effect:
    let
      existingWhen = effectWhen effect;
      existingAfter = effectAfter effect;
    in
    if existingWhen != { } then
      throw ''
        hci-effects.jobs.${jobName}: effect has a non-empty `when`; for
        `on.${kind}` jobs set conditions on `on.${kind}` instead.
      ''
    else if existingAfter != [ ] then
      throw ''
        hci-effects.jobs.${jobName}: effect has a non-empty `after`, but
        nixbot does not support `after` on `onEvent` effects.
      ''
    else
      let
        passthru = (effect.passthru or { }) // {
          inherit when;
          after = [ ];
        };
      in
      if effect ? overrideAttrs then
        effect.overrideAttrs (_old: {
          inherit passthru;
        })
      else
        effect
        // {
          inherit when passthru;
        };

  /*
    Build `onEvent.<kind>.<jobName>` attrs from jobs that declare event triggers.
  */
  mkOnEvent =
    jobs:
    lib.zipAttrsWith (_: lib.mergeAttrsList) (
      lib.mapAttrsToList (
        jobName: job:
        lib.listToAttrs (
          builtins.concatMap (
            kind:
            let
              raw = job.on.${kind} or null;
              when = whenFromOption kind raw;
            in
            if when == null then
              [ ]
            else
              [
                {
                  name = kind;
                  value = {
                    ${jobName} = withEventWhen jobName kind when job.effect;
                  };
                }
              ]
          ) eventKinds
        )
      ) jobs
    );

  /*
    Transform resolved jobs into `herculesCI` `onPush` / `onSchedule` /
    `onEvent` attrs.

    `on.push` must already be collapsed to `null` | `bool` (see
    `onPush.resolvePush`). Jobs with `on.push == null` are omitted from
    `onPush`; jobs with `on.schedule == null` are omitted from `onSchedule`.

    Each push/schedule job exposes a single effect at `outputs.effects.default`.
    Event jobs emit flat `onEvent.<kind>.<jobName>` effects with `when` set
    from `on.<kind>`.
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

      onEvent = mkOnEvent jobs;
    };
in
{
  inherit
    runIf
    mkOutputs
    mkOnEvent
    normalizeAfter
    normalizeAfterEntry
    withNormalizedAfter
    withEventWhen
    ;
}
