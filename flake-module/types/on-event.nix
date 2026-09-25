# `on.<event>` options → nixbot `herculesCI.onEvent.<kind>` + effect `when`.
{ lib }:
let
  inherit (lib)
    types
    mkOption
    ;

  coercedToList = t: types.coercedTo t (x: [ x ]) (types.listOf t);

  permissionType = types.enum [
    "read"
    "write"
    "admin"
  ];

  transitionType = types.enum [
    "broke"
    "fixed"
  ];

  statusType = coercedToList (
    types.enum [
      "succeeded"
      "failed"
    ]
  );

  stringListType = coercedToList types.str;

  whenKeyOptions = {
    permission = mkOption {
      type = types.nullOr permissionType;
      default = null;
      description = ''
        Minimum forge permission of the actor (or PR author, except on
        `comment` where only the commenter counts).
      '';
    };
    branches = mkOption {
      type = types.nullOr stringListType;
      default = null;
      description = ''
        fnmatch patterns matched against the PR base branch, or the built
        branch when there is no PR. The effect runs if any pattern matches.
      '';
    };
    status = mkOption {
      type = types.nullOr statusType;
      default = null;
      description = ''
        Allowed build statuses in the event payload (`succeeded` / `failed`).
      '';
    };
    labels = mkOption {
      type = types.nullOr stringListType;
      default = null;
      description = ''
        Labels the pull request must have (all of them).
      '';
    };
    modified = mkOption {
      type = types.nullOr stringListType;
      default = null;
      description = ''
        fnmatch patterns; the effect runs if any changed file on the PR
        matches any pattern.
      '';
    };
    commands = mkOption {
      type = types.nullOr stringListType;
      default = null;
      description = ''
        `/command` names that trigger this effect (without the leading `/`).
      '';
    };
    transition = mkOption {
      type = types.nullOr transitionType;
      default = null;
      description = ''
        Build status transition against the previous finished build of that
        branch or PR: `broke` or `fixed`.
      '';
    };
  };

  mkWhenModule =
    keys:
    {
      _file = ./on-event.nix;
      options = lib.genAttrs keys (key: whenKeyOptions.${key});
    };

  /*
    `null` — not declared for this event.
    `true` — declared with empty `when` (always match).
    attrset — declared; attrset becomes effect `when` (null fields omitted).
  */
  mkEventOption =
    kind: keys:
    mkOption {
      default = null;
      type = types.nullOr (
        types.either types.bool (
          types.submoduleWith {
            modules = [ (mkWhenModule keys) ];
          }
        )
      );
      description = ''
        Whether this job should run for nixbot `onEvent.${kind}` deliveries.

        - `null` — not declared for this event.
        - `true` — declared with an empty `when` (matches every delivery of this kind).
        - an attribute set — declared; the set is copied onto the effect as `when`
          (see the options below). Unset keys are omitted.

        Cannot be combined with `on.push` or `on.schedule` on the same job.
      '';
    };

  eventKinds = [
    "pull_request"
    "comment"
    "pull_request_closed"
    "build_finished"
  ];

  # Per-kind allowlists (keys that can actually match for that delivery).
  kindKeys = {
    pull_request = [
      "permission"
      "branches"
      "status"
      "labels"
      "modified"
    ];
    pull_request_closed = [
      "permission"
      "branches"
      "status"
      "labels"
      "modified"
    ];
    comment = [
      "permission"
      "branches"
      "status"
      "labels"
      "modified"
      "commands"
    ];
    build_finished = [
      "permission"
      "branches"
      "status"
      "transition"
    ];
  };

  onOptions = {
    pull_request = mkEventOption "pull_request" kindKeys.pull_request;
    comment = mkEventOption "comment" kindKeys.comment;
    pull_request_closed = mkEventOption "pull_request_closed" kindKeys.pull_request_closed;
    build_finished = mkEventOption "build_finished" kindKeys.build_finished;
  };

  /*
    Collapse an `on.<event>` value to the `when` attrset placed on the effect.
  */
  whenFromOption =
    kind: value:
    if value == null then
      null
    else if value == true then
      { }
    else if value == false then
      throw ''
        hci-effects: `on.${kind} = false` is not supported; use `null` to omit
        the event, or `true` / an attribute set for `when` conditions.
      ''
    else
      lib.filterAttrs (_: v: v != null) value;

  jobHasEvent =
    job: builtins.any (kind: job.on.${kind} or null != null) eventKinds;

  jobHasPushOrSchedule =
    job: (job.on.push or null) != null || (job.on.schedule or null) != null;

in
{
  inherit
    eventKinds
    kindKeys
    onOptions
    whenFromOption
    jobHasEvent
    jobHasPushOrSchedule
    ;
}
