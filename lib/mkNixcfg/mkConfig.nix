{
  lib,
  nixcfg,
}: config: let
in
  (lib.evalModules {
    specialArgs = { inherit lib nixcfg; };
    modules = [
      ./modules/nixcfg.nix
      {
        _file = (lib.unsafeGetAttrPos "name" config).file or null;
        inherit config;
      }
    ];
  })
  .config
