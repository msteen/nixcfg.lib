{
  nixpkgs,
  nixcfgs,
  mkDefaultModules,
  requireSops,
}: {
  inputs,
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
    optional
    singleton
    ;
in
  mkDefaultModules "home"
  ++ optional requireSops inputs.sops-nix.homeManagerModules.sops
  ++ modules
  ++ singleton {
    nixpkgs.overlays = [ (final: prev: channels) ] ++ catAttrs "overlay" nixcfgs;
    home = { inherit homeDirectory stateVersion username; };
    programs.home-manager.enable = true;
  }
