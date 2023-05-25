{
  self,
  lib,
}: {
  isPath = builtins.isPath or (x: builtins.typeOf x == "path");

  isPathLike = x: self.isStringLike x && self.isPathString (toString x);

  isPathString = lib.hasPrefix "/";

  isStringLike = x:
    lib.isString x
    || self.isPath x
    || x ? outPath
    || x ? __toString;
}
