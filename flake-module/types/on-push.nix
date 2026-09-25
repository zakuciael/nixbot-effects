{ lib }:
let
  inherit (lib)
    types
    mkOption
    ;

  fnmatch = import ./fnmatch.nix { inherit lib; };
  inherit (fnmatch) matchFnmatch matchAny fnmatchToRegex;

  coercedToList = t: types.coercedTo t (x: [ x ]) (types.listOf t);

  patternListType = coercedToList types.str;

  # `null` or `[]` → no filter for that family.
  normalizePatterns = patterns: if patterns == null || patterns == [ ] then null else patterns;

  /*
    Resolve `on.push` to `null` | `bool` given repo metadata.

    - `null` stays `null` (job not declared for push)
    - `false` → false
    - `true` / empty filters → true iff branch or tag is set
    - filter attrset → positive fnmatch lists on `branches` / `tags`
  */
  resolvePush =
    repo: value:
    if value == null then
      null
    else if value == false then
      false
    else if value == true then
      repo.branch != null || repo.tag != null
    else
      let
        branches = normalizePatterns (value.branches or null);
        tags = normalizePatterns (value.tags or null);
        hasBranchFilters = branches != null;
        hasTagFilters = tags != null;
      in
      if repo.branch == null && repo.tag == null then
        false
      else if repo.branch != null then
        if hasBranchFilters then
          matchAny branches repo.branch
        else if hasTagFilters then
          false
        else
          true
      else
        # on a tag
        if hasTagFilters then
          matchAny tags repo.tag
        else if hasBranchFilters then
          false
        else
          true;

  module = {
    _file = ./on-push.nix;
    options = {
      branches = mkOption {
        type = types.nullOr patternListType;
        default = null;
        description = ''
          fnmatch patterns matched against `config.repo.branch`. The job runs
          on a branch push when any pattern matches. An empty list is the same
          as omitting this option.

          If only `tags` is set, branch pushes do not run.
        '';
        example = [
          "main"
          "releases/*"
        ];
      };
      tags = mkOption {
        type = types.nullOr patternListType;
        default = null;
        description = ''
          fnmatch patterns matched against `config.repo.tag`. The job runs on
          a tag push when any pattern matches. An empty list is the same as
          omitting this option.

          If only `branches` is set, tag pushes do not run.
        '';
        example = [
          "v2"
          "v1.*"
        ];
      };
    };
  };

  option = mkOption {
    description = ''
      Whether this job should run when a Git ref is updated, such as when you
      push a commit or after you merge a pull request.

      - If `null`, the job is not declared for push events.
      - If `true` or `false`, the job is declared for push events, with the
        value used as the condition determining whether it actually runs.
      - If an attribute set, the job is declared for push events and filtered
        with positive `branches` / `tags` fnmatch lists (see the options
        below). An empty set is the same as `true`.

      Patterns use Python/`fnmatch` syntax (`*`, `?`, `[]`, `[!]`), the same
      dialect nixbot uses for event `when.branches` / `when.modified`. They
      are matched against `config.repo.branch` or `config.repo.tag` (the short
      ref name). `*` matches across `/`.
    '';
    inherit type;
    default = null;
  };

  type = types.nullOr (
    types.either types.bool (
      types.submoduleWith {
        modules = [ module ];
      }
    )
  );
in
{
  inherit
    option
    type
    module
    resolvePush
    normalizePatterns
    matchAny
    matchFnmatch
    fnmatchToRegex
    ;
}
