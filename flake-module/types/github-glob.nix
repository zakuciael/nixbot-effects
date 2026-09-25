# GitHub Actions filter-pattern → Nix regex.
# See https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#filter-pattern-cheat-sheet
{ lib }:
let
  inherit (lib) stringToCharacters escapeRegex;

  /*
    Convert a single GitHub Actions filter pattern (without a leading `!`)
    to a regex string suitable for `builtins.match`.

    Syntax (branch/tag filters):
    - `*` — zero or more chars except `/`
    - `**` — zero or more of any char
    - `?` — zero or one of the preceding atom (regex quantifier)
    - `+` — one or more of the preceding atom (regex quantifier)
    - `[]` — one alphanumeric / range as in the Actions docs
    - `\` — escape the next character as a literal
  */
  globToRegex =
    pattern:
    let
      chars = stringToCharacters pattern;

      # Parse a `[...]` character class starting at index `i` (on `[`).
      # Returns { regex, next }.
      parseClass =
        i:
        let
          len = builtins.length chars;
          go =
            j: acc:
            if j >= len then
              throw "github-glob: unclosed character class in pattern ${builtins.toJSON pattern}"
            else
              let
                c = builtins.elemAt chars j;
              in
              if c == "]" && acc != "" then
                {
                  regex = "[" + acc + "]";
                  next = j + 1;
                }
              else
                go (j + 1) (acc + c);
        in
        # First char after `[` may be `]` as a literal member.
        if i + 1 < len && builtins.elemAt chars (i + 1) == "]" then go (i + 2) "]" else go (i + 1) "";

      go =
        i: acc:
        if i >= builtins.length chars then
          acc
        else
          let
            c = builtins.elemAt chars i;
          in
          if c == "\\" then
            if i + 1 >= builtins.length chars then
              throw "github-glob: trailing backslash in pattern ${builtins.toJSON pattern}"
            else
              go (i + 2) (acc + escapeRegex (builtins.elemAt chars (i + 1)))
          else if c == "*" then
            if i + 1 < builtins.length chars && builtins.elemAt chars (i + 1) == "*" then
              go (i + 2) (acc + ".*")
            else
              go (i + 1) (acc + "[^/]*")
          else if c == "?" || c == "+" then
            # Quantifier on the preceding atom; pass through as regex.
            go (i + 1) (acc + c)
          else if c == "[" then
            let
              class = parseClass i;
            in
            go class.next (acc + class.regex)
          else
            go (i + 1) (acc + escapeRegex c);
    in
    go 0 "";

  matchGlob = pattern: name: builtins.match (globToRegex pattern) name != null;

in
{
  inherit globToRegex matchGlob;
}
