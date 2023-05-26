{ lib }: sources: nixcfgs: self: let
  constants = import ./constants.nix;

  allNixcfgs = let
    recurNixcfg = nixcfg: recur nixcfg.config.sources nixcfg.config.nixcfgs ++ [ nixcfg ];

    # This list of nixcfgs is still allowed to contain names and paths,
    # so we have to do additional filtering where necessary.
    recur = sources: nixcfgs: let
      nixcfgSources =
        lib.filterMapAttrs' (name: _: lib.hasPrefix constants.nixcfgPrefix name)
        (name: value: lib.nameValuePair (lib.removePrefix constants.nixcfgPrefix name) value)
        sources;
      missingNixcfgs = lib.attrNames (removeAttrs nixcfgSources (map (x:
        if lib.isAttrs x
        then x.config.name
        else if lib.isString x
        then x
        else "")
      nixcfgs));
      missingNixcfgSources = lib.filter (name: !nixcfgSources ? ${name}) (lib.filter (x: lib.isString x && !(lib.isPathString x)) nixcfgs);
    in
      if lib.length missingNixcfgs > 0
      then throw "The nixcfgs ${lib.concatNames missingNixcfgs} are listed as sources, but not configured in the nixcfgs list."
      else if lib.length missingNixcfgSources > 0
      then throw "The nixcfgs ${lib.concatNames missingNixcfgSources} miss corresponding sources prefixed with '${constants.nixcfgPrefix}'."
      else
        lib.concatMap (x:
          if lib.isAttrs x
          then [ x ]
          else
            recurNixcfg (import (
              if lib.isPathLike x
              then x
              else if lib.isString x
              then
                nixcfgSources.${x}
                or (throw "The nixcfg '${x}' has no known source.")
              else throw "One of the listed nixcfgs is neither a nixcfg attrset, a string reference to a known source, nor a path."
            )))
        nixcfgs;
  in
    recur sources nixcfgs ++ [ self ];

  # They will be deduplicated when converted to an attrset.
  nixcfgsAttrs = lib.mapToAttrs (nixcfg: lib.nameValuePair nixcfg.config.name nixcfg) allNixcfgs;

  # It can be very inefficient in Nix to check equality for complex values,
  # so we compare names instead and look the values back up in the attrset.
  nixcfgNames = lib.unique (map (x: x.config.name) allNixcfgs);
in {
  inherit nixcfgsAttrs;

  # An attrset is unordered, however `lib.unique` keeps the original order,
  # so we use the deduplicated list of names to rebuild the ordered list.
  nixcfgs = lib.attrVals nixcfgNames nixcfgsAttrs;
}
