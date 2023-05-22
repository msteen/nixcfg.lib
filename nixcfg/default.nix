{
  lib,
  nixcfg,
  sources,
  alejandraOverlay,
}: {
  mkNixcfg = import ./mkNixcfg.nix { inherit alejandraOverlay lib nixcfg sources; };
  mkNixcfgFlake = import ./mkNixcfgFlake.nix { inherit lib; };
}
