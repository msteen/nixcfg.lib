{
  self,
  lib,
}: {
  # The nixpkgs lib is extended with all builtins, because some of them are missing.
  # Even some of the older builtins. And for debugging purposes, and in case it can be useful,
  # the nixpkgs source used for the lib is also made available.
  # The reason we do not expose it as `path` is that it would conflict with `builtins.path`.
  mkNixpkgsLib = nixpkgs: (import (nixpkgs + "/lib")).extend (final: prev: { source = nixpkgs; } // builtins);
}
