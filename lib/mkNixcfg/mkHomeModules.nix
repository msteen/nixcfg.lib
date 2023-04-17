{
  nixpkgs,
  nixcfgs,
}: { stateVersion, ... }: username: {
  homeDirectory,
  modules,
}: let
  inherit
    (builtins)
    attrValues
    catAttrs
    concatMap
    ;
  inherit
    (nixpkgs.lib)
    singleton
    ;
in
  concatMap attrValues (catAttrs "homeModules" nixcfgs)
  ++ modules
  ++ singleton
  {
    home = { inherit homeDirectory stateVersion username; };
    programs.home-manager.enable = true;
  }
