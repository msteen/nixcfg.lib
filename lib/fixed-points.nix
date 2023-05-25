{
  self,
  lib,
}: {
  extendsList = overlays: initial: lib.fix (lib.foldl' (lib.flip lib.extends) initial overlays);

  extendNew = extensible: extensions: extensible.extend (final: prev: extensions // lib.intersectAttrs prev extensions);
}
