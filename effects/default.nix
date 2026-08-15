{ pkgs, inputs', ... }:
let
  inherit (pkgs) callPackage;

  mkEffect = callPackage ./mk-effect.nix { };
in
{
  inherit mkEffect;

  runClan = callPackage ./run-clan.nix {
    inherit mkEffect;
    inherit (inputs'.clan-core.packages) clan-cli;
  };

  runTerraform = callPackage ./run-terraform.nix {
    inherit mkEffect;
  };
}
