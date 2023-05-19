{
  self,
  lib,
}: {
  extendsList = overlays: initial: lib.fix (lib.foldl' (lib.flip lib.extends) initial overlays);
}
