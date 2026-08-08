{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options = {
    defaultEffectSystem = mkOption {
      type = types.str;
      default = "x86_64-linux";
      description = ''
        The default system type to run effects on.
      '';
    };
  };
}
