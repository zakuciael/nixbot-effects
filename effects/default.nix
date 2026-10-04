{ pkgs, ... }:
let
  inherit (pkgs) callPackage;
in
{
  mkEffect = callPackage ./mk-effect.nix { };
  # Runs a script on a host over ssh, like hercules-ci-effects' `ssh`.
  ssh = callPackage ./call-ssh.nix { };
}
