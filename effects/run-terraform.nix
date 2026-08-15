{
  mkEffect,
  opentofu,
  lib,
}:
{
  package ? opentofu,
  command ? "plan",
  extraArgs ? "",
  initBeforeRun ? true,
  ...
}@args:
let
  inherit (lib) optionalString getExe;

  terraformCli = getExe package;
in
mkEffect args
// {
  checkout = true;

  userSetupScript = optionalString initBeforeRun ''
    ${terraformCli} init
  '';

  effectScript = ''
    ${terraformCli} ${command} \
      ${extraArgs}
  '';
}
