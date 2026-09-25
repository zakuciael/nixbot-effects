# nix-unit tests for fnmatch (Python fnmatchcase-compatible).
{ lib }:
let
  inherit (import ../flake-module/types/fnmatch.nix { inherit lib; })
    fnmatchToRegex
    matchFnmatch
    matchAny
    ;
in
{
  testEmptyPattern = {
    expr = {
      matchEmpty = matchFnmatch "" "";
      matchNonEmpty = matchFnmatch "" "x";
    };
    expected = {
      matchEmpty = true;
      matchNonEmpty = false;
    };
  };

  testLiteral = {
    expr = {
      hit = matchFnmatch "main" "main";
      miss = matchFnmatch "main" "main2";
    };
    expected = {
      hit = true;
      miss = false;
    };
  };

  testStarCrossesSlash = {
    expr = {
      shallow = matchFnmatch "a/*/c" "a/b/c";
      deep = matchFnmatch "a/*/c" "a/b/x/c";
      starStar = matchFnmatch "a/**/c" "a/b/x/c";
      any = matchFnmatch "*" "a/b";
    };
    expected = {
      shallow = true;
      deep = true;
      starStar = true;
      any = true;
    };
  };

  testQuestionIsSingleChar = {
    expr = {
      one = matchFnmatch "a?c" "abc";
      zero = matchFnmatch "a?c" "ac";
      two = matchFnmatch "a?c" "abbc";
    };
    expected = {
      one = true;
      zero = false;
      two = false;
    };
  };

  testCharacterClass = {
    expr = {
      a = matchFnmatch "[abc]" "a";
      z = matchFnmatch "[abc]" "z";
      range = matchFnmatch "[a-c]" "b";
      literalClose = matchFnmatch "[]]" "]";
      literalOpen = matchFnmatch "[[]" "[";
    };
    expected = {
      a = true;
      z = false;
      range = true;
      literalClose = true;
      literalOpen = true;
    };
  };

  testNegatedClass = {
    expr = {
      hit = matchFnmatch "[!a]" "b";
      miss = matchFnmatch "[!a]" "a";
    };
    expected = {
      hit = true;
      miss = false;
    };
  };

  testPlusIsLiteral = {
    expr = {
      literal = matchFnmatch "ab+" "ab+";
      notQuantifier = matchFnmatch "ab+" "abbb";
    };
    expected = {
      literal = true;
      notQuantifier = false;
    };
  };

  testDotIsLiteral = {
    expr = {
      match = matchFnmatch "v1.*" "v1.9";
      noExtra = matchFnmatch "v1.*" "v1X9";
      regex = fnmatchToRegex "v1.*";
    };
    expected = {
      match = true;
      noExtra = false;
      regex = ''v1\..*'';
    };
  };

  testUnclosedClassIsLiteralBracket = {
    expr = matchFnmatch "[abc" "[abc";
    expected = true;
  };

  testMatchAny = {
    expr = {
      hit = matchAny [ "main" "dev" ] "main";
      miss = matchAny [ "main" "dev" ] "other";
      empty = matchAny [ ] "main";
    };
    expected = {
      hit = true;
      miss = false;
      empty = false;
    };
  };
}
