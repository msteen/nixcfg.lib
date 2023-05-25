{
  lib,
  nixcfg,
  sources,
  inputs,
}: {
  mkNixcfg = import ./mkNixcfg.nix { inherit lib nixcfg sources; };
  mkNixcfgFlake = import ./mkNixcfgFlake.nix { inherit inputs lib; };

  nixcfgPrefix = "nixcfg-";

  configurationTypes = [ "nixos" "container" "home" ];
}
