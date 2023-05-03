{ lib }: inputs: let
  inherit (inputs) self;
  nixcfgInputs = lib.attrValues (lib.filterAttrs (name: _: lib.hasPrefix "nixcfg-" name) inputs);
  nixcfgs = lib.concatLists (lib.catAttrs "nixcfgs" nixcfgInputs) ++ [ self ];
in rec {
  attrs = lib.mapToAttrs (nixcfg: lib.nameValuePair nixcfg.name nixcfg) nixcfgs;
  list = lib.attrVals (lib.unique (lib.catAttrs "name" nixcfgs)) attrs;
}
