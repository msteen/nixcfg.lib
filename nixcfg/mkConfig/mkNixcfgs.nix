{ lib }: sources: nixcfgs: self: let
  filterNixcfgSources = sources:
    lib.filterMapAttrs' (name: _: lib.hasPrefix "nixcfg-" name)
    (name: value: lib.nameValuePair (lib.removePrefix "nixcfg-" name) value)
    sources;

  # This list of nixcfgs is still allowed to contain names and paths,
  # so we have to do additional filtering where necessary.
  deduplicateNixcfgs = nixcfgs: let
    # They will be deduplicated when converted to an attrset.
    attrs =
      lib.mapToAttrs (nixcfg: lib.nameValuePair nixcfg.config.name nixcfg)
      (lib.filter lib.isAttrs nixcfgs);

    # It can be very inefficient in Nix to check equality for complex values,
    # so we compare names instead and look the values back up in the attrset.
    names = lib.unique (lib.filter lib.isString (map (x:
      if lib.isAttrs x
      then x.config.name
      else toString x)
    nixcfgs));

    # An attrset is unordered, however `lib.unique` keeps the original order,
    # so we use the deduplicated list of names to rebuild the ordered list.
    list = map (name: attrs.${name} or name) names;
  in { inherit attrs list names; };

  recurNixcfg = nixcfg: recur nixcfg.config.sources nixcfg.config.nixcfgs ++ [ nixcfg ];
  recur = sources: nixcfgs: let
    nixcfgSources = filterNixcfgSources sources;
    missingNixcfgs = lib.attrNames (removeAttrs nixcfgSources (map (x:
      if lib.isString x
      then x
      else x.config.name)
    nixcfgs));
    missingNixcfgSources = lib.filter (name: !nixcfgSources ? ${name}) (lib.filter lib.isString nixcfgs);
  in
    if lib.length missingNixcfgs > 0
    then throw "The nixcfgs ${lib.concatNames missingNixcfgs} are listed as sources, but not configured in the nixcfgs list."
    else if lib.length missingNixcfgSources > 0
    then throw "The nixcfgs ${lib.concatNames missingNixcfgSources} miss corresponding sources prefixed with 'nixcfg-'."
    else
      lib.concatMap (x:
        if lib.isAttrs x
        then [ x ]
        else
          recurNixcfg (import (
            if lib.hasPrefix "/" x
            then x
            else nixcfgSources.${x}
          )))
      nixcfgs;

  deduplicated = deduplicateNixcfgs (recur sources nixcfgs ++ [ self ]);
in {
  nixcfgs = deduplicated.list;
  nixcfgsAttrs = deduplicated.attrs;
}
