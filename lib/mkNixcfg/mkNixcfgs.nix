{ lib }: config: let
  nixcfgPrefix = "nixcfg-";

  nixcfgInputs =
    lib.filterMapAttrs (name: _: lib.hasPrefix nixcfgPrefix name)
    (name: value: lib.nameValuePair (lib.removePrefix nixcfgPrefix name) value)
    config.inputs;

  inputNixcfgs = let
    missingNixcfgs = lib.attrNames (removeAttrs nixcfgInputs config.nixcfgs);
    missingNixcfgInputs = lib.filter (name: !nixcfgInputs ? ${name}) config.nixcfgs;
  in
    if lib.length missingNixcfgs > 0
    then throw "The nixcfgs ${lib.concatNames missingNixcfgs} are listed as inputs, but not configured in the nixcfgs list."
    else if lib.length missingNixcfgInputs > 0
    then throw "The nixcfgs ${lib.concatNames missingNixcfgInputs} miss corresponding inputs prefixed with '${nixcfgPrefix}'."
    else lib.attrVals config.nixcfgs nixcfgInputs;

  # This may contain duplicates.
  allNixcfgs = lib.concatLists (lib.catAttrs "nixcfgs" inputNixcfgs) ++ [ config.inputs.self ];

  # They will be deduplicated when converted to an attrset.
  nixcfgsAttrs = lib.mapToAttrs (nixcfg: lib.nameValuePair nixcfg.config.name nixcfg) allNixcfgs;

  # It can be very inefficient in Nix to check equality for complex values,
  # so we compare names instead and look the values back up in the attrset.
  nixcfgNames = lib.unique (lib.mapGetAttrPath [ "config" "name" ] allNixcfgs);

  # An attrset is unordered, however `lib.unique` keeps the original order,
  # so we use the deduplicated list of names to rebuild the ordered list.
  nixcfgs = lib.attrVals nixcfgNames nixcfgsAttrs;
in {
  inherit nixcfgs nixcfgsAttrs;
}
