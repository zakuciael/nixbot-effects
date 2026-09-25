# nixbot-effects

A [flake-parts](https://flake.parts) module for declaring [NixBot](https://github.com/Mic92/nixbot) effects using a syntax that resembles [GitHub Actions](https://docs.github.com/en/actions) workflow files.

Instead of hand-writing the low-level `herculesCI.onPush.*.outputs.effects` attribute set, you describe _jobs_ with a single _effect_ and triggers (`on.push`, `on.schedule`, or `on.<event>`) — and the module produces the `flake.herculesCI` output for you.

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

A job is one effect plus the events that trigger it. Build the effect with `hci-effects.mkEffect`.

```nix
{ config, hci-effects, pkgs, self, ... }:
{
  hci-effects.jobs = {
    push-image = {
      # Run on pushes to main or any releases/* branch.
      on.push = {
        branches = [
          "main"
          "releases/*"
        ];
      };

      effect = hci-effects.mkEffect {
        inputs = [ pkgs.skopeo ];
        effectScript = ''
          skopeo copy --insecure-policy \
            docker-archive:${self.packages.x86_64-linux.image} \
            docker://registry.example.com/app:${config.repo.rev}
        '';
      };
    };

    # Starts only after `push-image` succeeded; the "staging" lock
    # makes concurrent deployments take turns updating staging.
    deploy-staging = {
      on.push = {
        branches = [
          "main"
          "releases/*"
        ];
      };

      effect = hci-effects.mkEffect {
        after = [ "push-image" ];
        lock = "staging";
        inputs = [ pkgs.kubectl ];
        effectScript = ''
          kubectl set image deployment/app app=registry.example.com/app:${config.repo.rev}
        '';
      };
    };

    flake-update = {
      # Run at 00:00 UTC on Sundays.
      on.schedule = {
        hour = [ 0 ];
        dayOfWeek = [ "Sun" ];
      };

      effect = hci-effects.mkEffect {
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

The module turns this into the `flake.herculesCI` output: `onPush.<job>.outputs.effects.default` for jobs with a non-`null` `on.push`, `onSchedule.<job>.outputs.effects.default` for jobs with an `on.schedule`, and `onEvent.<kind>.<job>` for event triggers.

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
| `after`            | `list`   | Effects that must succeed first (push/schedule only). Prefer short job names (`[ "push-image" ]`); full paths (`[ [ "push-image" "default" ] ]`) also work. Not allowed on event jobs. See [Ordering and locks](https://github.com/Mic92/nixbot/blob/main/docs/EFFECTS.md#ordering-and-locks). |
| `lock`             | `string` | Named lock (`{pr}` is expanded on event effects), see [Ordering and locks](https://github.com/Mic92/nixbot/blob/main/docs/EFFECTS.md#ordering-and-locks).                                                                                                              |
| `when`             | `attrs`  | Do not set on event jobs — use `on.<event>` instead. Ignored for push/schedule.                                                                                                                                                |

Any additional attribute given to `mkEffect` is passed straight through to `mkDerivation`, so you can set things like environment variables (`NIX_CONFIG = "..."`), hooks, or any other derivation attribute.

The effect derivation runs these phases:

1. `initPhase` — sets up `$HOME` and closes stdin
2. `getStatePhase` — runs `getStateScript`
3. `userSetupPhase` — runs `userSetupScript`
4. `effectPhase` — runs `effectScript`
5. `putStatePhase` — runs `putStateScript`

Each phase supports `pre`/`post` hooks (e.g. `preEffect`, `postEffect`), and state files can be downloaded/uploaded from within a script using the `getStateFile` / `putStateFile` bash functions.

### Bundled effects

The module argument also ships a few ready-made effects built on `mkEffect`:

### `hci-effects.runClan`

Runs `clan machines update` against your Clan machines.

| Argument      | Type     | Description                                                                          |
| ------------- | -------- | ------------------------------------------------------------------------------------ |
| `machines`    | `list`   | Machine names from the Clan inventory to update, passed as positional args.          |
| `tags`        | `list`   | Only update machines carrying these tags, passed as `--tags`.                         |
| `debug`       | `bool`   | Pass `--debug` to `clan machines update`.                                            |
| `extraArgs`   | `string` | Extra CLI arguments appended to the command.                                         |
| `inputs`      | `list`   | Extra packages to add to `nativeBuildInputs`.                                        |
| `secretsMap`  | `attrs`  | Secret mapping; defaults to `{ ssh = "clan-ssh"; age = "clan-age"; }`.               |

It requests a pushable checkout and wires up state/secrets for you: the age key is written for decrypting clan secrets, the SSH key for connecting to the machines, and `clan.known_hosts` is downloaded/uploaded via `getStateFile`/`putStateFile`. `--host-key-check accept-new` is always passed.

### `hci-effects.runTerraform`

Runs a Terraform/OpenTofu CLI command (e.g. `plan` or `apply`) against the checkout. By default `init` is run first (in the `userSetup` phase), so init failures abort the effect before the requested command executes.

| Argument     | Type     | Description                                                                 |
| ------------ | -------- | --------------------------------------------------------------------------- |
| `package`    | `package`| The CLI binary to use for init and the command (OpenTofu, Terraform, or any CLI-compatible package), defaults to `opentofu`. |
| `command`    | `string` | Any command accepted by the Terraform CLI (e.g. `"plan"`, `"apply"`, `"state"`, `"output"`), defaults to `"plan"`. |
| `extraArgs`  | `string` | Extra CLI arguments appended to the command.                                |
| `initBeforeRun` | `bool` | Run `init` before the command, defaults to `true`. Set to `false` when `init` output is generated at build time (e.g. by the [terranix](https://terranix.org/) flake-parts module) to avoid running `init` multiple times. |

It requests a pushable checkout. Since arbitrary derivations cover the `plan`/`apply` split, use `after` to order effects that apply after a plan passes review.

```nix
hci-effects.jobs = {
  plan = {
    on.push = true;
    effect = hci-effects.runTerraform {
      # `opentofu init` runs automatically before this.
      extraArgs = "-lock-timeout=5m";
    };
  };
  apply = {
    on.push = true;
    effect = hci-effects.runTerraform {
      after = [ "plan" ];
      command = "apply";
      extraArgs = "-auto-approve";
    };
  };
};
```

### `hci-effects.jobs.<job-id>.effect`

The job's effect derivation. You normally create it with `hci-effects.mkEffect`. Emitted as `onPush` / `onSchedule` → `outputs.effects.default`, or as `onEvent.<kind>.<job>` for event triggers.

### `hci-effects.jobs.<job-id>.on`

A job must set at least one trigger. `on.push` and `on.schedule` may be combined. Event triggers (`pull_request`, `comment`, `pull_request_closed`, `build_finished`) may be combined with each other, but not with `push` / `schedule`.

#### `on.push`

`null` (default; job not declared for push), a boolean, or a filter attribute set. Booleans both declare the job for push events and act as the `runIf` condition. An empty set `{ }` is the same as `true`.

You can still write a manual condition:

```nix
on.push = config.repo.branch == "main";
```

Or use positive fnmatch filters (matched against `config.repo.branch` / `config.repo.tag`):

| Attribute | Type | Meaning |
| --- | --- | --- |
| `branches` | string or list of strings | Run on a branch push when any pattern matches. Empty list ≡ omit. |
| `tags` | string or list of strings | Run on a tag push when any pattern matches. Empty list ≡ omit. |

Semantics:

- Only `branches` set → tag pushes do not run (and the other way around).
- Neither set → both branches and tags run.
- Patterns use Python/`fnmatch` syntax (`*`, `?`, `[]`, `[!]`), the same dialect nixbot uses for event conditions. `*` matches across `/`.

```nix
on.push = {
  branches = [ "main" "releases/*" ];
  tags = [ "v*" ];
};
```

#### `on.schedule`

`null` (default) or an attribute set with:

- `minute` — `null` or integer `0..59` (arbitrary when `null`)
- `hour` — `null` or int / list of ints `0..23`
- `dayOfWeek` — `null` or list of `"Mon"`..`"Sun"`
- `dayOfMonth` — `null` or list of ints `0..31`

All values are equality constraints evaluated in **UTC**. If `minute` or `hour` is omitted, an arbitrary time is picked. See the [hercules-ci-effects schedule reference](https://docs.hercules-ci.com/hercules-ci-effects/) for details.

#### `on.pull_request` / `on.comment` / `on.pull_request_closed` / `on.build_finished`

nixbot [event effects](https://github.com/Mic92/nixbot/blob/main/docs/EFFECTS.md#event-effects-onevent). `null` (default), `true` (empty `when`), or a `when` attribute set copied onto the emitted effect.

| `when` key | Type | Allowed on |
| --- | --- | --- |
| `permission` | `read` \| `write` \| `admin` | all four |
| `branches` | string or list (fnmatch) | all four |
| `status` | `succeeded` \| `failed` (or list) | all four |
| `labels` | string or list | `pull_request`, `pull_request_closed`, `comment` |
| `modified` | string or list (fnmatch) | `pull_request`, `pull_request_closed`, `comment` |
| `commands` | string or list | `comment` only |
| `transition` | `broke` \| `fixed` | `build_finished` only |

```nix
hci-effects.jobs = {
  plan = {
    on.pull_request = {
      permission = "write";
    };
    on.comment = {
      commands = [ "plan" ];
      permission = "write";
    };
    effect = hci-effects.mkEffect {
      checkout = true;
      lock = "infra";
      effectScript = ''
        tofu plan -no-color | nixbot-pr-comment --replace-marker plan
      '';
    };
  };

  broke = {
    on.build_finished = {
      branches = [ "main" ];
      transition = "broke";
    };
    effect = hci-effects.mkEffect {
      effectScript = ''echo "main broke: $NIXBOT_BUILD_URL"'';
    };
  };
};
```

### `hci-effects.repo`

Read-only repository metadata for the current checkout. Query it via the `config` module argument:

```nix
{ config, ... }:
{
  hci-effects.jobs.deploy = {
    on.push = true;
    effect = hci-effects.mkEffect {
      effectScript = ''
        echo "${config.repo.rev}"
      '';
    };
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
