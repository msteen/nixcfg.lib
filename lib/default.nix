{ nixpkgs }: let
  inherit (import ./sources.nix {
    lib = { };
    self = { };
  }) mkNixpkgsLib;

  lib = mkNixpkgsLib nixpkgs;

  inherit (import ./attrsets.nix {
    inherit lib;
    self = { };
  }) concatAttrs concatMapAttrs';

  inherit (import ./file-systems.nix {
    inherit lib;
    self = { inherit concatMapAttrs'; };
  }) listNix;

  self =
    lib.makeExtensible (self:
      concatAttrs (map (path: import path { inherit lib self; }) (lib.attrValues (listNix ./.))));
in
  self
