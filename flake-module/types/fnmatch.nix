# Shell-style pattern matching compatible with Python `fnmatch.fnmatchcase`
# (as used by nixbot for `when.branches` / `when.modified`).
#
# - `*` — any string (including `/`)
# - `?` — any single character
# - `[abc]` / `[a-c]` — character class
# - `[!abc]` — negated character class
# - Consecutive `*` are compressed
# - No quoting of meta-characters (a lone `\` is literal)
{ lib }:
let
  inherit (lib) stringToCharacters escapeRegex;

  /*
    Convert an fnmatch pattern to a regex string for `builtins.match`
    (full-string match).
  */
  fnmatchToRegex =
    pattern:
    let
      chars = stringToCharacters pattern;
      len = builtins.length chars;

      # Parse a `[...]` class starting at index `i` (on `[`).
      # Returns { regex, next } where next is the index after `]`,
      # or a literal-`[` fallback when the class is unclosed.
      parseClass =
        i:
        let
          # After `[`, optional `!`, optional `]` as a member, then to closing `]`.
          start = i + 1;
          afterBang =
            if start < len && builtins.elemAt chars start == "!" then start + 1 else start;
          afterCloseMember =
            if afterBang < len && builtins.elemAt chars afterBang == "]" then
              afterBang + 1
            else
              afterBang;

          findClose =
            j:
            if j >= len then
              null
            else if builtins.elemAt chars j == "]" then
              j
            else
              findClose (j + 1);

          close = findClose afterCloseMember;
        in
        if close == null then
          {
            regex = escapeRegex "[";
            next = i + 1;
          }
        else
          let
            body = builtins.substring start (close - start) pattern;
            negated = builtins.stringLength body > 0 && builtins.substring 0 1 body == "!";
            inner = if negated then builtins.substring 1 (builtins.stringLength body - 1) body else body;
          in
          if inner == "" then
            {
              # Empty class: never matches. Negated empty: any one char.
              regex = if negated then "." else "$.^";
              next = close + 1;
            }
          else
            let
              # Escape `^` / `[` when they would be special as the first class char.
              # Hyphen ranges are left as in the pattern (fnmatch passes them through).
              escapedInner =
                let
                  first = builtins.substring 0 1 inner;
                  rest = builtins.substring 1 (builtins.stringLength inner - 1) inner;
                  first' =
                    if first == "^" || first == "[" then "\\" + first else first;
                in
                first' + rest;
              classBody = if negated then "^" + escapedInner else escapedInner;
            in
            {
              regex = "[" + classBody + "]";
              next = close + 1;
            };

      go =
        i: acc:
        if i >= len then
          acc
        else
          let
            c = builtins.elemAt chars i;
          in
          if c == "*" then
            # Compress consecutive stars.
            let
              skip =
                j: if j < len && builtins.elemAt chars j == "*" then skip (j + 1) else j;
            in
            go (skip (i + 1)) (acc + ".*")
          else if c == "?" then
            go (i + 1) (acc + ".")
          else if c == "[" then
            let
              class = parseClass i;
            in
            go class.next (acc + class.regex)
          else
            go (i + 1) (acc + escapeRegex c);
    in
    go 0 "";

  matchFnmatch = pattern: name: builtins.match (fnmatchToRegex pattern) name != null;

  # True if any pattern matches (OR). Empty list → false.
  matchAny = patterns: name: builtins.any (pattern: matchFnmatch pattern name) patterns;

in
{
  inherit fnmatchToRegex matchFnmatch matchAny;
}
