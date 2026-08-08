{
  runCommand,
  stdenvNoCC,
  writers,
  cacert,
  curl,
  jq,
}:
let
  # Fetches a workload-identity ID token from nixbot inside the effect
  # sandbox, see docs/WORKLOAD_IDENTITY.md. --json prints the raw
  # {token, expires_at} response (niks3's ScriptToken format).
  idTokenScript = writers.writePython3Bin "nixbot-id-token" { } (
    builtins.readFile ./scripts/nixbot-id-token.py
  );

  effectSetupHook = runCommand "effects-setup-hook-sh" { } ''
    mkdir -p $out/nix-support
    cp ${./scripts/effects-setup-hook.sh} $out/nix-support/setup-hook
  '';
in

{
  effectScript ? "",
  userSetupScript ? "",
  getStateScript ? "",
  putStateScript ? "",
  name ? "effect",
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
  ...
}@attrs:
stdenvNoCC.mkDerivation (
  {
    inherit
      name
      effectScript
      userSetupScript
      getStateScript
      putStateScript
      ;
    # Attr paths are nested lists, which cannot be coerced into
    # derivation env vars; expose them via passthru instead.
    passthru = { inherit after lock; };
    isEffect = true;
    __nixbot_effect_checkout = checkout;
    secretsMap = builtins.toJSON secretsMap;
    idTokenAudiences = builtins.toJSON idTokenAudiences;

    nativeBuildInputs = [
      cacert
      curl
      jq
      effectSetupHook
    ]
    ++ (if idTokenAudiences != [ ] then [ idTokenScript ] else [ ])
    ++ inputs;

    phases = [
      "initPhase"
      "getStatePhase"
      "userSetupPhase"
      "effectPhase"
      "putStatePhase"
    ];

    userSetupPhase = ''
      runHook preUserSetup
      eval "$userSetupScript"
      runHook postUserSetup
    '';

    effectPhase = ''
      runHook preEffect
      eval "$effectScript"
      runHook postEffect
    '';

    getStatePhase = ''
      runHook preGetState
      eval "$getStateScript"
      runHook postGetState
      registerPutStatePhaseOnFailure
    '';

    putStatePhase = ''
      if [[ -z ''${PUT_STATE_DONE:-} ]]; then
        runHook prePutState
        eval "$putStateScript"
        runHook postPutState
        PUT_STATE_DONE=true
      else
        echo 1>&2 "NOTE: State has already been uploaded and was not uploaded again."
      fi
    '';

    initPhase = ''
      exec </dev/null
      export HOME=/build/home
      mkdir -p "$HOME"
    '';
  }
  // attrs
)
