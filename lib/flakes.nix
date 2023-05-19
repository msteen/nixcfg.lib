{
  self,
  lib,
}: {
  flakeCompat = let
    lock = lib.fromJSON (lib.readFile (./.. + "/flake.lock"));
  in
    import (lib.fetchTarball {
      url = "https://github.com/edolstra/flake-compat/archive/${lock.nodes.flake-compat.locked.rev}.tar.gz";
      sha256 = lock.nodes.flake-compat.locked.narHash;
    });

  importFlake = path: (self.flakeCompat { src = path; }).defaultNix;

  inputsToSources = inputs: lib.mapAttrs (_: input: input.outPath) (removeAttrs inputs [ "self" ]);
}
