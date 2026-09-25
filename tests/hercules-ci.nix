# nix-unit tests for herculesCI pure helpers (`runIf`, `mkOutputs`, onEvent).
{ lib }:
let
  inherit (import ../flake-module/hercules-ci-lib.nix { inherit lib; })
    runIf
    mkOutputs
    normalizeAfter
    withEventWhen
    ;

  # Stand-in for an effect derivation; only `inputDerivation` matters for runIf.
  mkEffect =
    name: after: when:
    {
      inherit name;
      inputDerivation = {
        inherit name;
        outPath = "/nix/store/fake-${name}";
      };
      passthru = {
        inherit after when;
        lock = null;
      };
      inherit after when;
    };

  effectA = mkEffect "a" [ ] { };
  effectB = mkEffect "b" [ ] { };
  effectC = mkEffect "c" [ ] { };
  effectWithShortAfter = mkEffect "dep" [ "deploy" ] { };
  effectWithFullAfter = mkEffect "dep" [
    [
      "deploy"
      "default"
    ]
  ] { };
  effectWithWhen = mkEffect "gated" [ ] { permission = "write"; };
  effectWithAfter = mkEffect "ordered" [ "other" ] { };

  nullEvents = {
    pull_request = null;
    comment = null;
    pull_request_closed = null;
    build_finished = null;
  };
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
        on = {
          push = true;
          schedule = null;
        }
        // nullEvents;
        effect = effectA;
      };
      flake-update = {
        on = {
          push = null;
          schedule = {
            hour = [ 0 ];
            dayOfWeek = [ "Sun" ];
          };
        }
        // nullEvents;
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
      onEvent = { };
    };
  };

  testMkOutputsKeepsFalsePushAsDependencies = {
    expr = mkOutputs {
      gated = {
        on = {
          push = false;
          schedule = null;
        }
        // nullEvents;
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
      onEvent = { };
    };
  };

  testMkOutputsOmitsNullTriggers = {
    expr = mkOutputs {
      idle = {
        on = {
          push = null;
          schedule = null;
        }
        // nullEvents;
        effect = effectA;
      };
    };
    expected = {
      onPush = { };
      onSchedule = { };
      onEvent = { };
    };
  };

  testMkOutputsBothTriggers = {
    expr = mkOutputs {
      dual = {
        on = {
          push = true;
          schedule = { minute = 15; };
        }
        // nullEvents;
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
      onEvent = { };
    };
  };

  testMkOutputsNormalizesAfter = {
    expr = {
      short = (mkOutputs {
        work = {
          on = {
            push = true;
            schedule = null;
          }
          // nullEvents;
          effect = effectWithShortAfter;
        };
      }).onPush.work.outputs.effects.default.run.after;
      full = (mkOutputs {
        work = {
          on = {
            push = true;
            schedule = null;
          }
          // nullEvents;
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

  testMkOutputsOnEvent = {
    expr =
      let
        out = mkOutputs {
          plan = {
            on = {
              push = null;
              schedule = null;
              pull_request = {
                permission = "write";
                labels = [ "preview" ];
                branches = null;
                status = null;
                modified = null;
              };
              comment = {
                commands = [ "plan" ];
                permission = "write";
                branches = null;
                status = null;
                labels = null;
                modified = null;
              };
              pull_request_closed = null;
              build_finished = null;
            };
            effect = effectA;
          };
          broke = {
            on = {
              push = null;
              schedule = null;
              pull_request = null;
              comment = null;
              pull_request_closed = null;
              build_finished = {
                transition = "broke";
                branches = [ "main" ];
                permission = null;
                status = null;
              };
            };
            effect = effectB;
          };
        };
      in
      {
        planPrWhen = out.onEvent.pull_request.plan.when;
        planCommentWhen = out.onEvent.comment.plan.when;
        brokeWhen = out.onEvent.build_finished.broke.when;
        noClosed = out.onEvent ? pull_request_closed;
      };
    expected = {
      planPrWhen = {
        permission = "write";
        labels = [ "preview" ];
      };
      planCommentWhen = {
        commands = [ "plan" ];
        permission = "write";
      };
      brokeWhen = {
        transition = "broke";
        branches = [ "main" ];
      };
      noClosed = false;
    };
  };

  testWithEventWhenRejectsExistingWhen = {
    expr = (builtins.tryEval (withEventWhen "plan" "pull_request" { } effectWithWhen)).success;
    expected = false;
  };

  testWithEventWhenRejectsAfter = {
    expr = (builtins.tryEval (withEventWhen "plan" "pull_request" { } effectWithAfter)).success;
    expected = false;
  };
}
