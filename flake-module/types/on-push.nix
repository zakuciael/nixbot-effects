{ lib }:
let
  inherit (lib)
    types
    mkOption
    hasPrefix
    removePrefix
    any
    all
    foldl'
    ;

  githubGlob = import ./github-glob.nix { inherit lib; };
  inherit (githubGlob) matchGlob globToRegex;

  coercedToList = t: types.coercedTo t (x: [ x ]) (types.listOf t);

  patternListType = coercedToList types.str;

  /*
    Ordered GitHub Actions include-list matching.
    A leading `!` negates: the last matching pattern wins.
  */
  matchIncludePatterns =
    patterns: name:
    foldl' (
      matched: pattern:
      if hasPrefix "!" pattern then
        if matchGlob (removePrefix "!" pattern) name then false else matched
      else if matchGlob pattern name then
        true
      else
        matched
    ) false patterns;

  matchIgnorePatterns =
    patterns: name: !(any (pattern: matchGlob pattern name) patterns);

  /*
    Match one ref family (branches or tags) given an include list and/or
    an ignore list. Caller must ensure they are not both non-null.
  */
  matchRefFilters =
    name: include: ignore:
    if include != null then
      matchIncludePatterns include name
    else if ignore != null then
      matchIgnorePatterns ignore name
    else
      true;

  checkPushFilters =
    value:
    if builtins.isBool value || value == null then
      value
    else
      let
        inherit (value) branches branchesIgnore tags tagsIgnore;
      in
      if branches != null && branchesIgnore != null then
        throw ''
          on.push: cannot set both `branches` and `branchesIgnore`.
          Use `branches` with `!` patterns to include and exclude.
        ''
      else if tags != null && tagsIgnore != null then
        throw ''
          on.push: cannot set both `tags` and `tagsIgnore`.
          Use `tags` with `!` patterns to include and exclude.
        ''
      else if branchesIgnore != null && any (hasPrefix "!") branchesIgnore then
        throw ''
          on.push.branchesIgnore: patterns must not start with `!`.
          Use `branches` with `!` patterns for include-and-exclude.
        ''
      else if tagsIgnore != null && any (hasPrefix "!") tagsIgnore then
        throw ''
          on.push.tagsIgnore: patterns must not start with `!`.
          Use `tags` with `!` patterns for include-and-exclude.
        ''
      else if
        branches != null && any (hasPrefix "!") branches && all (hasPrefix "!") branches
      then
        throw ''
          on.push.branches: a `!` pattern requires at least one positive
          (non-`!`) pattern in the same list.
        ''
      else if tags != null && any (hasPrefix "!") tags && all (hasPrefix "!") tags then
        throw ''
          on.push.tags: a `!` pattern requires at least one positive
          (non-`!`) pattern in the same list.
        ''
      else
        value;

  /*
    Resolve `on.push` to `null` | `bool` given repo metadata.

    - `null` stays `null` (job not declared for push)
    - `false` → false
    - `true` / empty filters → true iff branch or tag is set
    - filter attrset → Actions-exact branch/tag filter semantics
  */
  resolvePush =
    repo: value:
    let
      value' = checkPushFilters value;
    in
    if value' == null then
      null
    else if value' == false then
      false
    else if value' == true then
      repo.branch != null || repo.tag != null
    else
      let
        hasBranchFilters = value'.branches != null || value'.branchesIgnore != null;
        hasTagFilters = value'.tags != null || value'.tagsIgnore != null;
      in
      if repo.branch == null && repo.tag == null then
        false
      else if repo.branch != null then
        if hasBranchFilters then
          matchRefFilters repo.branch value'.branches value'.branchesIgnore
        else if hasTagFilters then
          false
        else
          true
      else
        # on a tag
        if hasTagFilters then
          matchRefFilters repo.tag value'.tags value'.tagsIgnore
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
          Glob patterns matched against `config.repo.branch`. Use this to
          include branches, or to include and exclude with ordered `!`
          patterns. Cannot be set together with `branchesIgnore`.

          If only tag filters are set, branch pushes do not run.
        '';
        example = [
          "main"
          "releases/**"
          "!releases/**-alpha"
        ];
      };
      branchesIgnore = mkOption {
        type = types.nullOr patternListType;
        default = null;
        description = ''
          Glob patterns matched against `config.repo.branch`. When set, the
          job runs on branch pushes unless the branch matches one of these
          patterns. Cannot be set together with `branches`. Patterns must not
          start with `!`; use `branches` with `!` for include-and-exclude.
        '';
        example = [
          "mona/octocat"
          "releases/**-alpha"
        ];
      };
      tags = mkOption {
        type = types.nullOr patternListType;
        default = null;
        description = ''
          Glob patterns matched against `config.repo.tag`. Use this to include
          tags, or to include and exclude with ordered `!` patterns. Cannot be
          set together with `tagsIgnore`.

          If only branch filters are set, tag pushes do not run.
        '';
        example = [
          "v2"
          "v1.*"
        ];
      };
      tagsIgnore = mkOption {
        type = types.nullOr patternListType;
        default = null;
        description = ''
          Glob patterns matched against `config.repo.tag`. When set, the job
          runs on tag pushes unless the tag matches one of these patterns.
          Cannot be set together with `tags`. Patterns must not start with
          `!`; use `tags` with `!` for include-and-exclude.
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
        with GitHub Actions-style `branches` / `branchesIgnore` / `tags` /
        `tagsIgnore` patterns (see the options below). An empty set is the
        same as `true`.

      Patterns use the GitHub Actions filter syntax (`*`, `**`, `?`, `+`,
      `[]`, `\`, and ordered `!` negation on include lists). They are matched
      against `config.repo.branch` or `config.repo.tag` (the short ref name).

      See: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#onpushbranchestagsbranches-ignoretags-ignore
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
    checkPushFilters
    matchIncludePatterns
    matchIgnorePatterns
    matchRefFilters
    globToRegex
    matchGlob
    ;
}
