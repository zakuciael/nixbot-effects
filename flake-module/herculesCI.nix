{
  config,
  lib,
  ...
}:
let
  inherit (import ./hercules-ci-lib.nix { inherit lib; }) mkOutputs;
in
{
  config = {
    flake.herculesCI =
      {
        primaryRepo ? throw "`<flake>.outputs.herculesCI` requires a `primaryRepo` argument.",
        ...
      }:
      mkOutputs (config.hci-effects primaryRepo);
  };
}
