{
  config,
  ...
}:
{
  config = {
    flake.herculesCI =
      {
        primaryRepo ? throw "`<flake>.outputs.herculesCI` requires a `primaryRepo` argument.",
        ...
      }:
      {
        onPush.default.outputs.effects = config.hci-effects primaryRepo;
      };
  };
}
