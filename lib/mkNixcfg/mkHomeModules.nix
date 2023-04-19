{
  nixpkgs,
  nixcfgs,
}: {
  stateVersion,
  channels,
  ...
}: username: {
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
    nixpkgs.overlays = [ (final: prev: channels) ] ++ catAttrs "overlay" nixcfgs;
    home = { inherit homeDirectory stateVersion username; };
    programs.home-manager.enable = true;
  }
