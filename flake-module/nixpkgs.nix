{ lib, ... }:
let
  inherit (lib) mkOptionDefault;
in
{
  hci-effects = { inputs', ... }: {
    _module.args.pkgs = mkOptionDefault (
      builtins.seq (inputs'.nixpkgs
        or (throw "flake-parts: The flake does not have a `nixpkgs` input. Please add it, or set `effects._module.args.pkgs` yourself.")
      ) inputs'.nixpkgs.legacyPackages
    );
  };
}
