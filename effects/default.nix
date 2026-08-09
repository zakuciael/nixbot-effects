{ pkgs, ... }: {
  mkEffect = pkgs.callPackage ./mk-effect.nix { };
}
