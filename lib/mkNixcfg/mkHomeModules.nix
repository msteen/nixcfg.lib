{
  lib,
  config,
  defaultOverlays,
  mkDefaultModules,
}: {
  name,
  sources,
  system,
  stateVersion,
  channels,
  pkgs,
  ...
}: username: {
  homeDirectory,
  modules,
}:
mkDefaultModules "home" name
++ lib.optional config.requireSops (sources.sops-nix + "/modules/home-manager/sops.nix")
++ modules
++ lib.singleton {
  nixpkgs.overlays = [ (final: prev: channels) ] ++ defaultOverlays;
  home = {
    inherit homeDirectory stateVersion username;
    packages = [ pkgs.alejandra ];
  };
  programs.home-manager.enable = true;
}
