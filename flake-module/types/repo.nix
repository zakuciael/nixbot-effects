{ lib }:
let
  inherit (lib) types mkOption;

  option = mkOption {
    description = ''
      The repository and checkout metadata of the current checkout, provided by Hercules CI.
      These options are read-only.

      You may read options by querying the `config` module argument.
    '';
    inherit type;
  };

  type = types.nullOr (types.submodule module);

  module = {
    _file = ./repo.nix;
    options = {
      ref = mkOption {
        type = types.str;
        readOnly = true;
        description = ''
          The git "ref" of the checkout.
        '';
        example = "refs/heads/main";
      };
      branch = mkOption {
        type = types.nullOr types.str;
        readOnly = true;
        description = ''
          The branch of the checkout. `null` when not on a branch; e.g. when on a tag.
        '';
        example = "main";
      };
      tag = mkOption {
        type = types.nullOr types.str;
        readOnly = true;
        description = ''
          The tag of the checkout. `null` when not on a tag; e.g. when on a branch.
        '';
        example = "1.0";
      };
      rev = mkOption {
        type = types.str;
        readOnly = true;
        description = ''
          The git revision, also known as the commit hash.
        '';
        example = "17ae1f614017447a983c34bb046892b3c571df52";
      };
      shortRev = mkOption {
        type = types.str;
        readOnly = true;
        description = ''
          An abbreviated `rev`.
        '';
        example = "17ae1f6";
      };
      remoteHttpUrl = mkOption {
        type = types.str;
        readOnly = true;
        description = ''
          HTTP url for cloning the repository.
        '';
        defaultText = lib.literalMD "";
      };
      remoteSshUrl = mkOption {
        type = types.str;
        readOnly = true;
        description = ''
          SSH url for cloning the repository.
        '';
        defaultText = lib.literalMD "";
      };
      webUrl = mkOption {
        type = types.str;
        readOnly = true;
        description = ''
          A URL to open the repository in the browser.
        '';
        defaultText = lib.literalMD "";
      };
      forgeType = mkOption {
        type = types.str;
        readOnly = true;
        description = ''
          What forge implementation hosts the repository.

          E.g. "github" or "gitlab"
        '';
        example = "github";
        defaultText = lib.literalMD "";
      };
      owner = mkOption {
        type = types.str;
        description = ''
          The owner of the repository.
        '';
        readOnly = true;
        defaultText = lib.literalMD "";
      };
      name = mkOption {
        type = types.str;
        description = ''
          The name of the repository.
        '';
        readOnly = true;
        defaultText = lib.literalMD "";
      };
    };
  };

in
{
  inherit option type module;
}
