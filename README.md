# nixbot-effects

A [flake-parts](https://flake.parts) module for declaring [NixBot](https://github.com/Mic92/nixbot) effects using a syntax that resembles [GitHub Actions](https://docs.github.com/en/actions) workflow files.

Instead of hand-writing the low-level `herculesCI.onPush.*.outputs.effects` attribute set, you describe _jobs_ with _steps_ and triggers (`on.push`, `on.schedule`) — and the module produces the `flake.herculesCI` output for you.

---

## Prerequisites

- [Nix](https://nixos.org/) with flakes enabled
- The target repository must use [flake-parts](https://flake.parts)
- A NixBot / Hercules CI agent evaluating the flake's `herculesCI` output

---

## Usage

Add the flake as an input and import its `flakeModule`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixbot-effects.url = "github:zakuciael/nixbot-effects";
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, nixbot-effects, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];

      imports = [
        nixbot-effects.flakeModules.default
      ];
    };
}
```

### Declaring jobs

A job is a set of _steps_ plus the events that trigger it. Each step is an effect built with `hci-effects.mkEffect`.

```nix
{ config, hci-effects, pkgs, self, ... }:
{
  hci-effects.jobs = {
    deploy = {
      # Run on every push.
      on.push = true;

      steps = {
        # Build and push the container image.
        push-image = hci-effects.mkEffect {
          inputs = [ pkgs.skopeo ];
          effectScript = ''
            skopeo copy --insecure-policy \
              docker-archive:${self.packages.x86_64-linux.image} \
              docker://registry.example.com/app:${config.repo.rev}
          '';
        };

        # Only starts after `push-image` succeeded; the "staging" lock
        # makes concurrent deployments take turns updating staging.
        deploy-staging = hci-effects.mkEffect {
          after = [ [ "deploy" "push-image" ] ];
          lock = "staging";
          inputs = [ pkgs.kubectl ];
          effectScript = ''
            kubectl set image deployment/app app=registry.example.com/app:${config.repo.rev}
          '';
        };
      };
    };

    flake-update = {
      # Run at 00:00 UTC on Sundays.
      on.schedule = {
        hour = [ 0 ];
        dayOfWeek = [ "Sun" ];
      };

      steps.update = hci-effects.mkEffect {
        # Ask nixbot for a writable checkout so we can commit the new lock.
        checkout = true;
        effectScript = ''
          nix flake update
          git commit -am "flake.lock: update"
          git push origin HEAD:update-flake-lock
        '';
      };
    };
  };
}
```

The module turns this into the `flake.herculesCI` output: `onPush.<job>` for jobs with a non-`null` `on.push`, and `onSchedule.<job>` for jobs with an `on.schedule`.

---

## Flake module reference

The exported `flakeModule` declares `hci-effects` and `defaultEffectSystem` as top-level flake-parts options.

> [!NOTE]
> The `hci-effects` **module argument** is distinct from the `hci-effects` **option**: the module argument exposes the bundled helper functions such as `mkEffect`, while the option holds your job declarations.

### `hci-effects.mkEffect` (module argument)

Produces an effect derivation, the function accepts the following arguments:

| Argument           | Type     | Description                                                                                                                                                                                                                      |
| ------------------ | -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `effectScript`     | `string` | The main script to run.                                                                                                                                                                                                          |
| `userSetupScript`  | `string` | Runs before `effectScript` (after `getStatePhase`).                                                                                                                                                                              |
| `getStateScript`   | `string` | Runs first, downloads state files.                                                                                                                                                                                               |
| `putStateScript`   | `string` | Runs last, uploads state files.                                                                                                                                                                                                  |
| `name`             | `string` | Derivation name, defaults to `"effect"`.                                                                                                                                                                                         |
| `inputs`           | `list`   | Extra packages added to `nativeBuildInputs`.                                                                                                                                                                                     |
| `secretsMap`       | `attrs`  | A map of named secrets to expose to the effect, see [Secrets](https://docs.hercules-ci.com/hercules-ci-agent/effects/declaration/#secrets).                                                                                      |
| `checkout`         | `bool`   | Request a pushable repository checkout at `/build/checkout` (exported as `$NIXBOT_EFFECT_CHECKOUT`), see [Pushable repository checkout](https://github.com/Mic92/nixbot/blob/main/docs/EFFECTS.md#pushable-repository-checkout). |
| `idTokenAudiences` | `list`   | Audiences for which this effect may request workload-identity ID tokens, see [Workload identity](https://github.com/Mic92/nixbot/blob/main/docs/WORKLOAD_IDENTITY.md).                                                           |
| `after`            | `list`   | Attribute paths of effects that must succeed first, e.g. `[ [ "deploy" "push-image" ] ]`, see [Ordering and locks](https://github.com/Mic92/nixbot/blob/main/docs/EFFECTS.md#ordering-and-locks).                                |
| `lock`             | `string` | Named lock, see [Ordering and locks](https://github.com/Mic92/nixbot/blob/main/docs/EFFECTS.md#ordering-and-locks).                                                                                                              |

Any additional attribute given to `mkEffect` is passed straight through to `mkDerivation`, so you can set things like environment variables (`NIX_CONFIG = "..."`), hooks, or any other derivation attribute.

The effect derivation runs these phases:

1. `initPhase` — sets up `$HOME` and closes stdin
2. `getStatePhase` — runs `getStateScript`
3. `userSetupPhase` — runs `userSetupScript`
4. `effectPhase` — runs `effectScript`
5. `putStatePhase` — runs `putStateScript`

Each phase supports `pre`/`post` hooks (e.g. `preEffect`, `postEffect`), and state files can be downloaded/uploaded from within a script using the `getStateFile` / `putStateFile` bash functions.

### `hci-effects.jobs.<job-id>.steps.<name>`

A step is any Nix package (an effect derivation). You normally create it with `hci-effects.mkEffect`.

### `hci-effects.jobs.<job-id>.on`

A job may set `push`, `schedule`, or both at once; jobs with neither are ignored.

- `push` — `null` (default; job not declared for push), `true`, or `false`. A boolean value both declares the job for push events _and_ acts as the condition for whether it runs.
- `schedule` — `null` (default) or an attribute set with:
  - `minute` — `null` or integer `0..59` (arbitrary when `null`)
  - `hour` — `null` or int / list of ints `0..23`
  - `dayOfWeek` — `null` or list of `"Mon"`..`"Sun"`
  - `dayOfMonth` — `null` or list of ints `0..31`

All values are equality constraints evaluated in **UTC**. If `minute` or `hour` is omitted, an arbitrary time is picked. See the [hercules-ci-effects schedule reference](https://docs.hercules-ci.com/hercules-ci-effects/) for details.

### `hci-effects.repo`

Read-only repository metadata for the current checkout. Query it via the `config` module argument:

```nix
{ config, ... }:
{
  hci-effects.jobs.deploy.steps.print = hci-effects.mkEffect {
    effectScript = ''
      echo "${config.repo.rev}"
    '';
  };
}
```

Available fields: `ref`, `branch`, `tag`, `rev`, `shortRev`, `remoteHttpUrl`, `remoteSshUrl`, `webUrl`, `forgeType`, `owner`, `name`. Same set as the upstream [hercules-ci-effects repo options](https://docs.hercules-ci.com/hercules-ci-effects/).

### `defaultEffectSystem`

The default system effects evaluate on. Set at the top level of the flake module:

```nix
{
  defaultEffectSystem = "aarch64-linux"; # default: "x86_64-linux"
}
```

### Helper bash functions

These bash functions are available in every effect script (derived from and compatible with [hercules-ci-effects](https://docs.hercules-ci.com/hercules-ci-effects/)):

- `getStateFile <name> [file]` / `putStateFile <name> [file]` — download / upload state files
- `readSecretString <secret> <path>` / `readSecretJSON <secret> <path>` — read secrets from `$HERCULES_CI_SECRETS_JSON`
- `writeAWSSecret`, `writeSSHKey`, `writeDockerKey`, `useDockerHost`, `writeGPGKey`, `gpgFingerprints`, `gpgTrust`
- `writeAgeKey` — writes an age key from a secret (used for [sops](https://github.com/getsops/sops))
- `registerPutStatePhaseOnFailure` — register `putStatePhase` to run on failure

---

## License

Distributed under the MIT license. See the [LICENSE](LICENSE) file for more information.
