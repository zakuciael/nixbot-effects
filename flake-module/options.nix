{
  self,
  config,
  lib,
  flake-parts-lib,
  ...
}:
let
  inherit (lib)
    mkOption
    types
    mapAttrs
    escapeNixIdentifier
    ;
  inherit (flake-parts-lib) mkPerSystemType;

  rootConfig = config;
in
{
  options = {
    hci-effects = mkOption {
      type = mkPerSystemType (
        { system, ... }:
        {
          _file = ./flake-module.nix;
          options = {
            repo = (import ./types/repo.nix { inherit lib; }).option;

            jobs = mkOption {
              type = types.lazyAttrsOf (
                types.submodule {
                  options = {
                    steps = mkOption {
                      type = types.lazyAttrsOf types.package;
                    };
                    on = {
                      push = (import ./types/on-push.nix { inherit lib; }).option;
                      schedule = (import ./types/on-schedule.nix { inherit lib; }).option;
                    };
                  };
                }
              );
            };
          };

          config = {
            _module.args = {
              inputs' = mapAttrs (
                inputName: input:
                builtins.addErrorContext
                  "while retrieving system-dependent attributes for input ${escapeNixIdentifier inputName}"
                  (
                    if input._type or null == "flake" then
                      rootConfig.perInput system input
                    else
                      throw "Trying to retrieve system-dependent attributes for input ${escapeNixIdentifier inputName}, but this input is not a flake. Perhaps flake = false was added to the input declarations by mistake, or you meant to use a different input, or you meant to use plain old inputs, not inputs'."
                  )
              ) self.inputs;

              self' = builtins.addErrorContext "while retrieving system-dependent attributes for a flake's own outputs" (
                rootConfig.perInput system self
              );
            };
          };
        }
      );

      apply =
        modules: primaryRepo:
        (lib.evalModules {
          modules = [
            {
              _file = "herculesCI parameters";
              config = {
                # Filter out values which are unavailable and therefore null.
                repo = {
                  inherit (primaryRepo) ref rev shortRev;
                  branch = primaryRepo.branch or null;
                  tag = primaryRepo.tag or null;
                }
                // lib.filterAttrs (k: v: v != null) {
                  remoteHttpUrl = primaryRepo.remoteHttpUrl or null;
                  remoteSshUrl = primaryRepo.remoteSshUrl or null;
                  webUrl = primaryRepo.webUrl or null;
                  forgeType = primaryRepo.forgeType or null;
                  owner = primaryRepo.owner or null;
                  name = primaryRepo.name or null;
                };
              };
            }
          ]
          ++ modules;
          prefix = [ "hci-effects" ];
          specialArgs = {
            system = config.defaultEffectSystem;
          };
          class = "hci-effects";
        }).config.jobs;
    };
  };
}
