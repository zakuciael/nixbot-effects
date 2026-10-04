{
  runCommand,
  stdenvNoCC,
  writers,
  cacert,
  curl,
  jq,
  bash,
  coreutils,
  lib,
}:
let
  inherit (lib)
    getExe
    filter
    concatStringsSep
    splitString
    ;

  # Fetches a workload-identity ID token from nixbot inside the effect
  # sandbox, see docs/WORKLOAD_IDENTITY.md. --json prints the raw
  # {token, expires_at} response (niks3's ScriptToken format).
  idTokenScript = writers.writePython3Bin "nixbot-id-token" { } (
    builtins.readFile ./scripts/nixbot-id-token.py
  );

  # Posts/updates a PR comment from an onEvent effect, see docs/EFFECTS.md.
  prCommentScript = writers.writePython3Bin "nixbot-pr-comment" { } (
    builtins.readFile ./scripts/nixbot-pr-comment.py
  );

  # hercules-ci-effects' shell functions (readSecretString, writeSSHKey,
  # getStateFile, ...). Same derivation name as upstream's.
  effectSetupHook = runCommand "effects-setup-hook-sh" { } /* bash */ ''
    mkdir -p $out/nix-support
    # The headers file holds the task token. Upstream puts it in $PWD, which
    # is the repository clone with checkout = true; $TMPDIR is /build.
    sed 's|\$PWD/hercules-ci.headers|$TMPDIR/hercules-ci.headers|' \
      ${./scripts/effects-setup-hook.sh} >$out/nix-support/setup-hook
  '';

  customFunctions = runCommand "effects-custom-funcs-sh" { } /* bash */ ''
    mkdir -p $out/nix-support
    cp ${./scripts/effects-custom-funcs.sh} $out/nix-support/setup-hook
  '';
in

{
  name,
  effectScript,
  userSetupScript ? "",
  inputs ? [ ],
  secretsMap ? { },

  # Pushable repository checkout at /build/checkout ($NIXBOT_EFFECT_CHECKOUT),
  # see https://github.com/Mic92/nixbot/blob/main/docs/EFFECTS.md
  checkout ? false,
  # Audiences this effect may request workload-identity ID tokens
  # for via `nixbot-id-token <audience>`, see https://github.com/Mic92/nixbot/blob/main/docs/WORKLOAD_IDENTITY.md
  idTokenAudiences ? [ ],
  # Scheduling metadata read via `nixbot-effects list`: attribute paths
  # of effects that must succeed first, job name first
  # (e.g. [ [ "default" "deploy-staging" ] ]), and a named lock
  # serializing runs across builds.
  after ? [ ],
  lock ? null,
  # onEvent only: conditions nixbot checks against the event before
  # running, see https://github.com/Mic92/nixbot/blob/main/docs/EFFECTS.md. `lock` may contain `{pr}` there.
  when ? { },

  getStateScript ? "",
  putStateScript ? "",
  priorCheckScript ? "",
  effectCheckScript ? "",
  preGetStatePhases ? "",
  preEffectPhases ? "priorCheckPhase",
  postEffectPhases ? "effectCheckPhase",
  passthru ? { },
  # Like upstream's mkEffect, any other attribute goes to mkDerivation
  # (e.g. runNixOS sets dontUnpack and passthru.prebuilt).
  ...
}@args:
stdenvNoCC.mkDerivation (
  removeAttrs args [
    "inputs"
    "checkout"
    "idTokenAudiences"
    "after"
    "lock"
    "when"
  ]
  // {
    inherit
      name
      effectScript
      userSetupScript
      getStateScript
      putStateScript
      priorCheckScript
      effectCheckScript
      ;
    # Attr paths are nested lists, which cannot be coerced into
    # derivation env vars; expose them via passthru instead.
    passthru = { inherit after lock when; };
    isEffect = true;

    __nixbot_effect_checkout = checkout;
    # like upstream hercules-ci-effects
    __hci_effect_fsroot_copy = runCommand "mkEffect-root" { } ''
      mkdir -p $out/bin $out/usr/bin
      ln -s ${getExe bash} $out/bin/sh
      ln -s ${coreutils}/bin/env $out/usr/bin/env
    '';

    secretsMap = builtins.toJSON secretsMap;
    idTokenAudiences = builtins.toJSON idTokenAudiences;

    nativeBuildInputs = [
      cacert
      curl
      jq
      effectSetupHook
      customFunctions
      prCommentScript
    ]
    ++ (if idTokenAudiences != [ ] then [ idTokenScript ] else [ ])
    ++ inputs;

    phases =
      [
        "initPhase"
        preGetStatePhases
        "getStatePhase"
        "userSetupPhase"
        preEffectPhases
        "effectPhase"
        "putStatePhase"
        postEffectPhases
      ]
      |> filter (p: p != "")
      |> concatStringsSep " "
      |> splitString " ";

    initPhase = ''
      exec </dev/null
      # The setup hook prepares the state API's credentials here.
      runHook preInit
      export HOME=/build/home
      mkdir -p "$HOME"
      echo "root:x:$(id -u):$(id -g):root:$HOME:/bin/sh" >> /etc/passwd
      mkdir -p ~/.ssh
      echo "BatchMode yes" >> ~/.ssh/config
      runHook postInit
    '';

    getStatePhase = ''
      runHook preGetState
      eval "$getStateScript"
      runHook postGetState
      registerPutStatePhaseOnFailure
    '';

    userSetupPhase = ''
      runHook preUserSetup
      eval "$userSetupScript"
      runHook postUserSetup
    '';

    # A failing check must not stop the effect: it may fix the problem.
    priorCheckPhase = ''
      runHook prePriorCheck
      if [[ -n "$priorCheckScript" ]] && ! eval "$priorCheckScript"; then
        echo 1>&2 "WARNING: prior check failed, continuing"
      fi
      runHook postPriorCheck
    '';

    effectPhase = ''
      runHook preEffect
      eval "$effectScript"
      runHook postEffect
    '';

    # Runs on failure too, see registerPutStatePhaseOnFailure.
    putStatePhase = ''
      if [[ -z ''${PUT_STATE_DONE:-} ]]; then
        runHook prePutState
        eval "$putStateScript"
        runHook postPutState
        PUT_STATE_DONE=true
      fi
    '';

    effectCheckPhase = ''
      runHook preEffectCheck
      eval "$effectCheckScript"
      runHook postEffectCheck
    '';
  }
)
