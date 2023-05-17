{ lib }: sources: nixcfgs: self: let
  recurNixcfg = nixcfg: recur nixcfg.config.sources nixcfg.config.nixcfgs ++ [ nixcfg ];
  recur = sources: nixcfgs: let
    nixcfgSources = lib.filterNixcfgSources sources;
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

  deduplicated = lib.deduplicateNixcfgs (recur sources nixcfgs ++ [ self ]);
in {
  nixcfgs = deduplicated.list;
  nixcfgsAttrs = deduplicated.attrs;
}
