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
    optionals
    singleton
    ;
in
  mkDefaultModules "home"
  ++ optionals requireSops [
    inputs.sops-nix.homeManagerModules.sops
    ./profiles/sops.nix
  ]
  ++ modules
  ++ singleton {
    nixpkgs.overlays = [ (final: prev: channels) ] ++ catAttrs "overlay" nixcfgs;
    home = { inherit homeDirectory stateVersion username; };
    programs.home-manager.enable = true;
  }
