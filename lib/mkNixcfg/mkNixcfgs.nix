{ lib }: self: let
  recur = nixcfg: let
    inherit (nixcfg) config;
    nixcfgSources = lib.filterNixcfgSources config.sources;
    missingNixcfgs = lib.attrNames (removeAttrs nixcfgSources (map (x:
      if lib.isString x
      then x
      else x.config.name)
    config.nixcfgs));
    missingNixcfgSources = lib.filter (name: !nixcfgSources ? ${name}) (lib.filter lib.isString config.nixcfgs);
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
          recur (import (
            if lib.hasPrefix "/" x
            then x
            else nixcfgSources.${x}
          )))
      config.nixcfgs
      ++ [ nixcfg ];

  deduplicated = lib.deduplicateNixcfgs (recur self);
in {
  nixcfgs = deduplicated.list;
  nixcfgsAttrs = deduplicated.attrs;
}
