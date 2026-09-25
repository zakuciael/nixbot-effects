# nix-unit tests for on-event when helpers.
{ lib }:
let
  inherit (import ../flake-module/types/on-event.nix { inherit lib; })
    whenFromOption
    jobHasEvent
    jobHasPushOrSchedule
    ;

  nullEvents = {
    pull_request = null;
    comment = null;
    pull_request_closed = null;
    build_finished = null;
  };
in
{
  testWhenFromTrue = {
    expr = whenFromOption "pull_request" true;
    expected = { };
  };

  testWhenFromNull = {
    expr = whenFromOption "pull_request" null;
    expected = null;
  };

  testWhenFromFalseThrows = {
    expr = (builtins.tryEval (whenFromOption "comment" false)).success;
    expected = false;
  };

  testWhenOmitsNulls = {
    expr = whenFromOption "pull_request" {
      permission = "write";
      labels = [ "preview" ];
      branches = null;
      status = null;
      modified = null;
    };
    expected = {
      permission = "write";
      labels = [ "preview" ];
    };
  };

  testJobHasEvent = {
    expr = {
      withPr = jobHasEvent {
        on = nullEvents // {
          pull_request = true;
        };
      };
      without = jobHasEvent {
        on = {
          push = true;
          schedule = null;
        }
        // nullEvents;
      };
    };
    expected = {
      withPr = true;
      without = false;
    };
  };

  testJobHasPushOrSchedule = {
    expr = {
      push = jobHasPushOrSchedule {
        on = {
          push = true;
          schedule = null;
        }
        // nullEvents;
      };
      eventOnly = jobHasPushOrSchedule {
        on = nullEvents // {
          comment = true;
        };
      };
    };
    expected = {
      push = true;
      eventOnly = false;
    };
  };
}
