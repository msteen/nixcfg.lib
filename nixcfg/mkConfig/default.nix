{ lib }: config: let
in
  (lib.evalModules {
    modules = [
      ../../modules/nixcfg.nix
      {
        _file = (lib.unsafeGetAttrPos "name" config).file or null;
        inherit config;
      }
    ];
  })
  .config
