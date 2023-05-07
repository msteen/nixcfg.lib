{
  lib,
  config,
  nixcfgs,
  mkDefaultModules,
}: {
  name,
  inputs,
  stateVersion,
  channels,
  ...
}: username: {
  homeDirectory,
  modules,
}:
mkDefaultModules "home" name
++ lib.optional config.requireSops inputs.sops-nix.homeManagerModules.sops
++ modules
++ lib.singleton {
  nixpkgs.overlays = [ (final: prev: channels) ] ++ lib.catAttrs "overlay" nixcfgs;
  home = { inherit homeDirectory stateVersion username; };
  programs.home-manager.enable = true;
}
