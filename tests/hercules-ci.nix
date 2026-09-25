# nix-unit tests for herculesCI pure helpers (`runIf`, `mkOutputs`).
{ lib }:
let
  inherit (import ../flake-module/hercules-ci-lib.nix { inherit lib; })
    runIf
    mkOutputs
    normalizeAfter
    ;

  # Stand-in for an effect derivation; only `inputDerivation` matters for runIf.
  mkEffect =
    name: after:
    {
      inherit name;
      inputDerivation = {
        inherit name;
        outPath = "/nix/store/fake-${name}";
      };
      passthru = {
        inherit after;
        lock = null;
        when = { };
      };
      inherit after;
    };

  effectA = mkEffect "a" [ ];
  effectB = mkEffect "b" [ ];
  effectC = mkEffect "c" [ ];
  effectWithShortAfter = mkEffect "dep" [ "deploy" ];
  effectWithFullAfter = mkEffect "dep" [
    [
      "deploy"
      "default"
    ]
  ];
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

  # --- normalizeAfter ---

  testNormalizeAfterShortAndFull = {
    expr = normalizeAfter [
      "deploy"
      [
        "other"
        "default"
      ]
    ];
    expected = [
      [
        "deploy"
        "default"
      ]
      [
        "other"
        "default"
      ]
    ];
  };

  # --- mkOutputs ---

  testMkOutputsRoutesPushAndSchedule = {
    expr = mkOutputs {
      deploy = {
        on.push = true;
        on.schedule = null;
        effect = effectA;
      };
      flake-update = {
        on.push = null;
        on.schedule = {
          hour = [ 0 ];
          dayOfWeek = [ "Sun" ];
        };
        effect = effectB;
      };
    };
    expected = {
      onPush = {
        deploy = {
          outputs.effects = {
            default = { run = effectA; };
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
            default = effectB;
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
        effect = effectC;
      };
    };
    expected = {
      onPush = {
        gated = {
          outputs.effects = {
            default = {
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
        effect = effectA;
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
        effect = effectA;
      };
    };
    expected = {
      onPush = {
        dual = {
          outputs.effects = {
            default = { run = effectA; };
          };
        };
      };
      onSchedule = {
        dual = {
          when = { minute = 15; };
          outputs.effects = {
            default = effectA;
          };
        };
      };
    };
  };

  testMkOutputsNormalizesAfter = {
    expr = {
      short = (mkOutputs {
        work = {
          on.push = true;
          on.schedule = null;
          effect = effectWithShortAfter;
        };
      }).onPush.work.outputs.effects.default.run.after;
      full = (mkOutputs {
        work = {
          on.push = true;
          on.schedule = null;
          effect = effectWithFullAfter;
        };
      }).onPush.work.outputs.effects.default.run.after;
    };
    expected = {
      short = [
        [
          "deploy"
          "default"
        ]
      ];
      full = [
        [
          "deploy"
          "default"
        ]
      ];
    };
  };
}
