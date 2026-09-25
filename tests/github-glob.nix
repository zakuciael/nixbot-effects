# nix-unit tests for GitHub Actions filter-pattern → regex conversion.
{ lib }:
let
  inherit (import ../flake-module/types/github-glob.nix { inherit lib; })
    globToRegex
    matchGlob
    ;

  evalOk = expr: builtins.tryEval expr;
in
{
  testEmptyPattern = {
    expr = {
      regex = globToRegex "";
      matchEmpty = matchGlob "" "";
      matchNonEmpty = matchGlob "" "x";
    };
    expected = {
      regex = "";
      matchEmpty = true;
      matchNonEmpty = false;
    };
  };

  testCharacterClass = {
    expr = {
      a = matchGlob "[abc]" "a";
      z = matchGlob "[abc]" "z";
      range = matchGlob "[a-c]" "b";
      literalClose = matchGlob "[]x]" "]";
    };
    expected = {
      a = true;
      z = false;
      range = true;
      literalClose = true;
    };
  };

  testStarDoesNotCrossSlash = {
    expr = {
      shallow = matchGlob "a/*/c" "a/b/c";
      deep = matchGlob "a/*/c" "a/b/x/c";
      starStar = matchGlob "a/**/c" "a/b/x/c";
    };
    expected = {
      shallow = true;
      deep = false;
      starStar = true;
    };
  };

  testPlusQuantifier = {
    expr = {
      one = matchGlob "ab+" "ab";
      many = matchGlob "ab+" "abbb";
      none = matchGlob "ab+" "a";
    };
    expected = {
      one = true;
      many = true;
      none = false;
    };
  };

  testEscapeSpecials = {
    expr = {
      star = matchGlob ''\*'' "*";
      q = matchGlob ''\?'' "?";
      plus = matchGlob ''\+'' "+";
      notStar = matchGlob ''\*'' "x";
    };
    expected = {
      star = true;
      q = true;
      plus = true;
      notStar = false;
    };
  };

  testTrailingBackslashThrows = {
    expr = (evalOk (globToRegex ''foo\'' )).success;
    expected = false;
  };

  testUnclosedClassThrows = {
    expr = (evalOk (globToRegex "[abc")).success;
    expected = false;
  };
}
