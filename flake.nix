{
  description = "A flake-parts module for declaring NixBot effects similarly to the GitHub Actions Workflow syntax";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    nix-unit = {
      url = "github:nix-community/nix-unit";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      flake-parts,
      nix-unit,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { self, ... }:
      {
        debug = true;

        imports = [
          nix-unit.modules.flake.default
        ];

        systems = [
          "x86_64-linux"
          "aarch64-linux"
          "aarch64-darwin"
        ];

        flake = {
          flakeModule = self.flakeModules.default;
          flakeModules.default = ./flake-module/default.nix;
        };

        perSystem = { lib, ... }: {
          nix-unit = {
            inputs = { inherit nixpkgs flake-parts nix-unit; };
            tests = {
              on-push = import ./tests/on-push.nix { inherit lib; };
              fnmatch = import ./tests/fnmatch.nix { inherit lib; };
              hercules-ci = import ./tests/hercules-ci.nix { inherit lib; };
              on-event = import ./tests/on-event.nix { inherit lib; };
            };
          };
        };
      }
    );
}
