{ pkgs }:
let
  # Fetches a workload-identity ID token from nixbot inside the effect
  # sandbox, see docs/WORKLOAD_IDENTITY.md. --json prints the raw
  # {token, expires_at} response (niks3's ScriptToken format).
  idTokenScript = pkgs.writers.writePython3Bin "nixbot-id-token" { } (
    builtins.readFile ./scripts/nixbot-id-token.py
  );

  effectSetupHook = pkgs.runCommand "effects-setup-hook-sh" { } ''
    mkdir -p $out/nix-support
    cp ${./scripts/effects-setup-hook.sh} $out/nix-support/setup-hook
  '';
in

{
  effectScript ? "",
  userSetupScript ? "",
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
pkgs.stdenvNoCC.mkDerivation (
  {
    inherit name effectScript userSetupScript;
    # Attr paths are nested lists, which cannot be coerced into
    # derivation env vars; expose them via passthru instead.
    passthru = { inherit after lock; };
    isEffect = true;
    __nixbot_effect_checkout = checkout;
    secretsMap = builtins.toJSON secretsMap;
    idTokenAudiences = builtins.toJSON idTokenAudiences;

    nativeBuildInputs = [
      pkgs.cacert
      pkgs.curl
      pkgs.jq
      effectSetupHook
    ]
    ++ (if idTokenAudiences != [ ] then [ idTokenScript ] else [ ])
    ++ inputs;

    phases = [
      "initPhase"
      "userSetupPhase"
      "effectPhase"
    ];

    userSetupPhase = ''eval "$userSetupScript"'';
    effectPhase = ''eval "$effectScript"'';
    initPhase = ''
      exec </dev/null
      export HOME=/build/home
      mkdir -p "$HOME"
    '';
  }
  // attrs
)
