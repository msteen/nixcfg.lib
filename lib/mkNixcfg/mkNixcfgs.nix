{ lib }: inputs: let
  inherit (inputs) self;
  nixcfgInputs = lib.attrValues (lib.filterAttrs (name: _: lib.hasPrefix "nixcfg-" name) inputs);
  nixcfgs = lib.concatLists (lib.catAttrs "nixcfgs" nixcfgInputs) ++ [ self ];
  nixcfgsAttrs = lib.mapToAttrs (nixcfg: lib.nameValuePair nixcfg.config.name nixcfg) nixcfgs;
in {
  inherit nixcfgsAttrs;

  # It can be very inefficient in Nix to check equality for complex values,
  # so we compare names instead and look the values back up in the attrset.
  nixcfgs = lib.attrVals (lib.unique (lib.mapGetAttrPath [ "config" "name" ] nixcfgs)) nixcfgsAttrs;
}
