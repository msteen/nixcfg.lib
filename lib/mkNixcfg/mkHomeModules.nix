{
  lib,
  config,
  defaultOverlays,
  mkDefaultModules,
}: {
  name,
  inputs,
  system,
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
++ lib.singleton (let
  inherit (config.inputs) self;
in {
  nixpkgs.overlays = [ (final: prev: channels) ] ++ defaultOverlays;
  home = {
    inherit homeDirectory stateVersion username;
    packages = [ self.formatter.${system} ];
  };
  programs.home-manager.enable = true;
})
