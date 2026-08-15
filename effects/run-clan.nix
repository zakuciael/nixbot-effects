{
  mkEffect,
  clan-cli,
  openssh,

  lib,
}:
let
  inherit (lib) concatStringsSep optionalString;

  toArgs = list: concatStringsSep " " list;
in
{
  machines ? [ ],
  tags ? [ ],
  debug ? false,
  extraArgs ? "",
  inputs ? [ ],
  secretsMap ? {
    "ssh" = "clan-ssh";
    "age" = "clan-age";
  },
  ...
}@args:
(
  mkEffect args
  // {
    inherit secretsMap;

    # Env
    knownHostsName = "clan.known_hosts";

    checkout = true;

    inputs = [
      clan-cli
      openssh
    ]
    ++ inputs;

    getStateScript = ''
      mkdir -p ~/.ssh
      getStateFile "$knownHostsName" ~/.ssh/known_hosts
      touch ~/.ssh/known_hosts
    '';

    putStateScript = ''
      putStateFile "$knownHostsName" ~/.ssh/known_hosts
    '';

    # Age key is needed for decrypting clan secrets and SSH key for connecting to the machines
    userSetupScript = ''
      writeAgeKey
      writeSSHKey
    '';

    effectScript = ''
      clan machines update \
        --host-key-check accept-new \
        ${optionalString debug "--debug"} \
        ${extraArgs} \
        ${optionalString (tags != [ ]) "--tags ${toArgs tags}"} \
        ${toArgs machines}
    '';
  }
)
