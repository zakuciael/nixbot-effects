{ lib }:
let
  inherit (lib) types mkOption;

  option = mkOption {
    description = ''
      Whether this job should run when a Git ref is updated, such as when you push a commit or after you merge a pull request.

      - If `null`, the job is not declared for push events.
      - If `true` or `false`, the job is declared for push events, with
        the value used as the condition determining whether it actually
        runs.
    '';
    inherit type;
    default = null;
  };

  type = types.nullOr types.bool;
in
{
  inherit option type;
}
