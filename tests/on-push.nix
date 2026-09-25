# nix-unit tests for on.push filter helpers.
# Run: nix flake check
# Or:  nix run nixpkgs#nix-unit -- --flake .#tests
{ lib }:
let
  onPush = import ../flake-module/types/on-push.nix { inherit lib; };
  inherit (onPush)
    globToRegex
    matchGlob
    matchIncludePatterns
    matchIgnorePatterns
    matchRefFilters
    resolvePush
    checkPushFilters
    ;

  repoBranch = {
    branch = "main";
    tag = null;
  };

  repoTag = {
    branch = null;
    tag = "v1.9.1";
  };

  repoNeither = {
    branch = null;
    tag = null;
  };

  # Helpers so throw-tests stay readable.
  evalOk = expr: builtins.tryEval expr;
in
{
  # --- globToRegex / matchGlob ---

  testGlobLiteral = {
    expr = matchGlob "main" "main";
    expected = true;
  };

  testGlobLiteralReject = {
    expr = matchGlob "main" "main2";
    expected = false;
  };

  testGlobStarNoSlash = {
    expr = {
      match = matchGlob "feature/*" "feature/my-branch";
      noNested = matchGlob "feature/*" "feature/beta/my-branch";
    };
    expected = {
      match = true;
      noNested = false;
    };
  };

  testGlobStarStar = {
    expr = {
      nested = matchGlob "feature/**" "feature/beta/my-branch";
      shallow = matchGlob "feature/**" "feature/your-branch";
      all = matchGlob "**" "all/the/branches";
    };
    expected = {
      nested = true;
      shallow = true;
      all = true;
    };
  };

  testGlobQuestionQuantifier = {
    # `?` is "zero or one of the preceding character", not "any char".
    expr = {
      js = matchGlob "*.jsx?" "page.js";
      jsx = matchGlob "*.jsx?" "page.jsx";
      jsxx = matchGlob "*.jsx?" "page.jsxx";
    };
    expected = {
      js = true;
      jsx = true;
      jsxx = false;
    };
  };

  testGlobPlusAndClass = {
    expr = {
      v1 = matchGlob "v[12].[0-9]+.[0-9]+" "v1.10.1";
      v2 = matchGlob "v[12].[0-9]+.[0-9]+" "v2.0.0";
      v3 = matchGlob "v[12].[0-9]+.[0-9]+" "v3.0.0";
    };
    expected = {
      v1 = true;
      v2 = true;
      v3 = false;
    };
  };

  testGlobEscape = {
    expr = matchGlob ''feature/\*'' "feature/*";
    expected = true;
  };

  testGlobDotIsLiteral = {
    expr = {
      regex = globToRegex "v1.*";
      match = matchGlob "v1.*" "v1.9";
      noExtra = matchGlob "v1.*" "v1X9";
    };
    expected = {
      regex = ''v1\.[^/]*'';
      match = true;
      noExtra = false;
    };
  };

  # --- include / ignore lists ---

  testIncludeWithNegation = {
    expr = {
      keep = matchIncludePatterns [ "releases/**" "!releases/**-alpha" ] "releases/10";
      drop = matchIncludePatterns [
        "releases/**"
        "!releases/**-alpha"
      ] "releases/beta/3-alpha";
      other = matchIncludePatterns [ "releases/**" "!releases/**-alpha" ] "main";
    };
    expected = {
      keep = true;
      drop = false;
      other = false;
    };
  };

  testIgnorePatterns = {
    expr = {
      ignored = matchIgnorePatterns [ "mona/octocat" "releases/**-alpha" ] "mona/octocat";
      allowed = matchIgnorePatterns [ "mona/octocat" "releases/**-alpha" ] "main";
    };
    expected = {
      ignored = false;
      allowed = true;
    };
  };

  # --- resolvePush ---

  testResolveBoolTrue = {
    expr = resolvePush repoBranch true;
    expected = true;
  };

  testResolveBoolFalse = {
    expr = resolvePush repoBranch false;
    expected = false;
  };

  testResolveNull = {
    expr = resolvePush repoBranch null;
    expected = null;
  };

  testResolveEmptyFilters = {
    expr = resolvePush repoBranch {
      branches = null;
      branchesIgnore = null;
      tags = null;
      tagsIgnore = null;
    };
    expected = true;
  };

  testResolveNeitherRef = {
    expr = {
      withTrue = resolvePush repoNeither true;
      withFilters = resolvePush repoNeither {
        branches = [ "main" ];
        branchesIgnore = null;
        tags = null;
        tagsIgnore = null;
      };
    };
    expected = {
      withTrue = false;
      withFilters = false;
    };
  };

  testResolveBranchesOnly = {
    expr = {
      onMain = resolvePush repoBranch {
        branches = [ "main" ];
        branchesIgnore = null;
        tags = null;
        tagsIgnore = null;
      };
      onTag = resolvePush repoTag {
        branches = [ "main" ];
        branchesIgnore = null;
        tags = null;
        tagsIgnore = null;
      };
    };
    expected = {
      onMain = true;
      onTag = false;
    };
  };

  testResolveTagsOnly = {
    expr = {
      onTag = resolvePush repoTag {
        branches = null;
        branchesIgnore = null;
        tags = [ "v1.*" ];
        tagsIgnore = null;
      };
      onBranch = resolvePush repoBranch {
        branches = null;
        branchesIgnore = null;
        tags = [ "v1.*" ];
        tagsIgnore = null;
      };
    };
    expected = {
      onTag = true;
      onBranch = false;
    };
  };

  testResolveBranchesIgnore = {
    expr = resolvePush { branch = "mona/octocat"; tag = null; } {
      branches = null;
      branchesIgnore = [ "mona/octocat" ];
      tags = null;
      tagsIgnore = null;
    };
    expected = false;
  };

  testResolveStringCoercionViaList = {
    # Pattern lists are already lists after the module type; resolve sees lists.
    expr = resolvePush repoBranch {
      branches = [ "main" ];
      branchesIgnore = null;
      tags = null;
      tagsIgnore = null;
    };
    expected = true;
  };

  # --- checkPushFilters errors ---

  testCheckBothBranchesFilters = {
    expr = (evalOk (
      checkPushFilters {
        branches = [ "main" ];
        branchesIgnore = [ "dev" ];
        tags = null;
        tagsIgnore = null;
      }
    )).success;
    expected = false;
  };

  testCheckNegationOnIgnore = {
    expr = (evalOk (
      checkPushFilters {
        branches = null;
        branchesIgnore = [ "!main" ];
        tags = null;
        tagsIgnore = null;
      }
    )).success;
    expected = false;
  };

  testCheckOnlyNegation = {
    expr = (evalOk (
      checkPushFilters {
        branches = [ "!main" ];
        branchesIgnore = null;
        tags = null;
        tagsIgnore = null;
      }
    )).success;
    expected = false;
  };

  testCheckOk = {
    expr = checkPushFilters {
      branches = [
        "releases/**"
        "!releases/**-alpha"
      ];
      branchesIgnore = null;
      tags = null;
      tagsIgnore = null;
    };
    expected = {
      branches = [
        "releases/**"
        "!releases/**-alpha"
      ];
      branchesIgnore = null;
      tags = null;
      tagsIgnore = null;
    };
  };

  testCheckBothTagsFilters = {
    expr = (evalOk (
      checkPushFilters {
        branches = null;
        branchesIgnore = null;
        tags = [ "v*" ];
        tagsIgnore = [ "v1.*" ];
      }
    )).success;
    expected = false;
  };

  testCheckNegationOnTagsIgnore = {
    expr = (evalOk (
      checkPushFilters {
        branches = null;
        branchesIgnore = null;
        tags = null;
        tagsIgnore = [ "!v1.*" ];
      }
    )).success;
    expected = false;
  };

  testCheckOnlyNegationTags = {
    expr = (evalOk (
      checkPushFilters {
        branches = null;
        branchesIgnore = null;
        tags = [ "!v1.*" ];
        tagsIgnore = null;
      }
    )).success;
    expected = false;
  };

  # --- matchRefFilters ---

  testMatchRefFiltersInclude = {
    expr = {
      hit = matchRefFilters "main" [ "main" "dev" ] null;
      miss = matchRefFilters "other" [ "main" "dev" ] null;
      ignoreHit = matchRefFilters "main" null [ "main" ];
      ignoreMiss = matchRefFilters "dev" null [ "main" ];
      neither = matchRefFilters "anything" null null;
    };
    expected = {
      hit = true;
      miss = false;
      ignoreHit = false;
      ignoreMiss = true;
      neither = true;
    };
  };

  # --- resolvePush mixed / tagsIgnore ---

  testResolveTagsIgnore = {
    expr = {
      ignored = resolvePush repoTag {
        branches = null;
        branchesIgnore = null;
        tags = null;
        tagsIgnore = [ "v1.*" ];
      };
      allowed = resolvePush { branch = null; tag = "v2.0.0"; } {
        branches = null;
        branchesIgnore = null;
        tags = null;
        tagsIgnore = [ "v1.*" ];
      };
    };
    expected = {
      ignored = false;
      allowed = true;
    };
  };

  testResolveBothFamiliesOnBranch = {
    # Branch filters + tag filters: branch push uses branch filters only.
    expr = {
      onMain = resolvePush repoBranch {
        branches = [ "main" ];
        branchesIgnore = null;
        tags = [ "v*" ];
        tagsIgnore = null;
      };
      onOther = resolvePush { branch = "dev"; tag = null; } {
        branches = [ "main" ];
        branchesIgnore = null;
        tags = [ "v*" ];
        tagsIgnore = null;
      };
      onTag = resolvePush repoTag {
        branches = [ "main" ];
        branchesIgnore = null;
        tags = [ "v1.*" ];
        tagsIgnore = null;
      };
    };
    expected = {
      onMain = true;
      onOther = false;
      onTag = true;
    };
  };

  testResolveBranchFiltersRejectTag = {
    # Only branch filters → tag pushes do not run.
    expr = resolvePush repoTag {
      branches = [ "main" ];
      branchesIgnore = null;
      tags = null;
      tagsIgnore = null;
    };
    expected = false;
  };

  testResolveTagFiltersRejectBranch = {
    # Only tag filters → branch pushes do not run.
    expr = resolvePush repoBranch {
      branches = null;
      branchesIgnore = null;
      tags = [ "v*" ];
      tagsIgnore = null;
    };
    expected = false;
  };
}
