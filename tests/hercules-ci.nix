# nix-unit tests for herculesCI pure helpers (`runIf`, `mkOutputs`).
{ lib }:
let
  inherit (import ../flake-module/hercules-ci-lib.nix { inherit lib; })
    runIf
    mkOutputs
    ;

  # Stand-in for an effect derivation; only `inputDerivation` matters for runIf.
  mkEffect =
    name:
    {
      inherit name;
      inputDerivation = {
        inherit name;
        outPath = "/nix/store/fake-${name}";
      };
    };

  effectA = mkEffect "a";
  effectB = mkEffect "b";
  effectC = mkEffect "c";
in
{
  # --- runIf ---

  testRunIfTrue = {
    expr = runIf true effectA;
    expected = { run = effectA; };
  };

  testRunIfFalse = {
    expr = runIf false effectA;
    expected = {
      dependencies = effectA.inputDerivation // {
        isEffect = false;
        buildDependenciesOnly = true;
      };
    };
  };

  # --- mkOutputs ---

  testMkOutputsRoutesPushAndSchedule = {
    expr = mkOutputs {
      deploy = {
        on.push = true;
        on.schedule = null;
        steps = {
          push-image = effectA;
        };
      };
      flake-update = {
        on.push = null;
        on.schedule = {
          hour = [ 0 ];
          dayOfWeek = [ "Sun" ];
        };
        steps = {
          update = effectB;
        };
      };
    };
    expected = {
      onPush = {
        deploy = {
          outputs.effects = {
            push-image = { run = effectA; };
          };
        };
      };
      onSchedule = {
        flake-update = {
          when = {
            hour = [ 0 ];
            dayOfWeek = [ "Sun" ];
          };
          outputs.effects = {
            update = effectB;
          };
        };
      };
    };
  };

  testMkOutputsKeepsFalsePushAsDependencies = {
    # `on.push = false` still declares the job for push events; effects are
    # dependency-only via runIf.
    expr = mkOutputs {
      gated = {
        on.push = false;
        on.schedule = null;
        steps = {
          step = effectC;
        };
      };
    };
    expected = {
      onPush = {
        gated = {
          outputs.effects = {
            step = {
              dependencies = effectC.inputDerivation // {
                isEffect = false;
                buildDependenciesOnly = true;
              };
            };
          };
        };
      };
      onSchedule = { };
    };
  };

  testMkOutputsOmitsNullTriggers = {
    expr = mkOutputs {
      idle = {
        on.push = null;
        on.schedule = null;
        steps = {
          noop = effectA;
        };
      };
    };
    expected = {
      onPush = { };
      onSchedule = { };
    };
  };

  testMkOutputsBothTriggers = {
    expr = mkOutputs {
      dual = {
        on.push = true;
        on.schedule = { minute = 15; };
        steps = {
          work = effectA;
        };
      };
    };
    expected = {
      onPush = {
        dual = {
          outputs.effects = {
            work = { run = effectA; };
          };
        };
      };
      onSchedule = {
        dual = {
          when = { minute = 15; };
          outputs.effects = {
            work = effectA;
          };
        };
      };
    };
  };
}
