{
  hci-effects = { pkgs, ... }: {
    _module.args.hci-effects = import ../effects/default.nix { inherit pkgs; };
  };
}
