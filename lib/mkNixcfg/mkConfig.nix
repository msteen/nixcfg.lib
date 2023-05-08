{
  lib,
  nixcfg,
}: config: let
in
  (lib.evalModules {
    modules = [
      (import ./modules/nixcfg.nix { inherit lib nixcfg; })
      {
        _file = (lib.unsafeGetAttrPos "name" config).file or null;
        inherit config;
      }
    ];
  })
  .config
