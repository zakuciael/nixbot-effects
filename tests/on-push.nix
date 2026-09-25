# nix-unit tests for on.push filter helpers.
# Run: nix flake check
# Or:  nix run nixpkgs#nix-unit -- --flake .#tests
{ lib }:
let
  onPush = import ../flake-module/types/on-push.nix { inherit lib; };
  inherit (onPush) resolvePush normalizePatterns matchAny;

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
in
{
  testNormalizeEmptyList = {
    expr = {
      empty = normalizePatterns [ ];
      null_ = normalizePatterns null;
      keep = normalizePatterns [ "main" ];
    };
    expected = {
      empty = null;
      null_ = null;
      keep = [ "main" ];
    };
  };

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
      tags = null;
    };
    expected = true;
  };

  testResolveEmptyPatternLists = {
    # `[]` is treated like `null` (no filter).
    expr = resolvePush repoBranch {
      branches = [ ];
      tags = [ ];
    };
    expected = true;
  };

  testResolveNeitherRef = {
    expr = {
      withTrue = resolvePush repoNeither true;
      withFilters = resolvePush repoNeither {
        branches = [ "main" ];
        tags = null;
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
        tags = null;
      };
      onTag = resolvePush repoTag {
        branches = [ "main" ];
        tags = null;
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
        tags = [ "v1.*" ];
      };
      onBranch = resolvePush repoBranch {
        branches = null;
        tags = [ "v1.*" ];
      };
    };
    expected = {
      onTag = true;
      onBranch = false;
    };
  };

  testResolveStarCrossesSlash = {
    expr = resolvePush { branch = "feature/beta/x"; tag = null; } {
      branches = [ "feature/*" ];
      tags = null;
    };
    expected = true;
  };

  testResolveMatchAny = {
    expr = {
      hit = matchAny [ "main" "dev" ] "dev";
      miss = matchAny [ "main" "dev" ] "other";
    };
    expected = {
      hit = true;
      miss = false;
    };
  };

  testResolveBothFamiliesOnBranch = {
    expr = {
      onMain = resolvePush repoBranch {
        branches = [ "main" ];
        tags = [ "v*" ];
      };
      onOther = resolvePush { branch = "dev"; tag = null; } {
        branches = [ "main" ];
        tags = [ "v*" ];
      };
      onTag = resolvePush repoTag {
        branches = [ "main" ];
        tags = [ "v1.*" ];
      };
    };
    expected = {
      onMain = true;
      onOther = false;
      onTag = true;
    };
  };

  testResolveBranchFiltersRejectTag = {
    expr = resolvePush repoTag {
      branches = [ "main" ];
      tags = null;
    };
    expected = false;
  };

  testResolveTagFiltersRejectBranch = {
    expr = resolvePush repoBranch {
      branches = null;
      tags = [ "v*" ];
    };
    expected = false;
  };
}
