{ pkgs, ... }:
let
  inherit (pkgs) callPackage;
in
{
  mkEffect = callPackage ./mk-effect.nix { };
}
