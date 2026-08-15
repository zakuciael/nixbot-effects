{
  hci-effects = { pkgs, inputs', ... }: {
    _module.args.hci-effects = import ../effects/default.nix { inherit pkgs inputs'; };
  };
}
