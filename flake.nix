{
  description = "A flake-parts module for declaring NixBot effects similarly to the GitHub Actions Workflow syntax";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    clan-core = {
      url = "github:zakuciael/clan-core";
      inputs = {
        flake-parts.follows = "flake-parts";
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { self, ... }: {
        systems = [
          "x86_64-linux"
          "aarch64-linux"
          "aarch64-darwin"
        ];

        flake = {
          flakeModule = self.flakeModules.default;
          flakeModules.default = ./flake-module/default.nix;
        };
      }
    );
}
