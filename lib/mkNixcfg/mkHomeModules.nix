{
  nixpkgs,
  nixcfgs,
  mkDefaultModules,
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
    catAttrs
    ;
  inherit
    (nixpkgs.lib)
    singleton
    ;
in
  mkDefaultModules "home"
  ++ modules
  ++ singleton {
    nixpkgs.overlays = [ (final: prev: channels) ] ++ catAttrs "overlay" nixcfgs;
    home = { inherit homeDirectory stateVersion username; };
    programs.home-manager.enable = true;
  }
