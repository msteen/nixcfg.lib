{
  nixpkgs,
  nixcfg,
}: let
  inherit
    (builtins)
    attrNames
    concatMap
    concatStringsSep
    elemAt
    foldl'
    head
    isAttrs
    isFunction
    length
    listToAttrs
    mapAttrs
    readDir
    zipAttrsWith
    ;
  inherit
    (nixpkgs.lib)
    const
    extends
    fix
    flip
    hasPrefix
    hasSuffix
    recursiveUpdate
    removeSuffix
    singleton
    ;
in rec {
  traceJSON = x: builtins.trace (builtins.toJSON x) x;
  traceJSONMap = f: x: builtins.trace (builtins.toJSON (f x)) x;
  traceJSONValue = value: traceJSONMap (const value);

  concatAttrs = foldl' (a: b: a // b) { };
  concatAttrsRecursive = foldl' (a: b: recursiveUpdate a b) { };

  optionalInherit = attrs: names:
    listToAttrs (concatMap (name:
      if attrs ? ${name}
      then [
        {
          inherit name;
          value = attrs.${name};
        }
      ]
      else [ ])
    names);

  applyAttrs = let
    recurDefault = lhs:
      if isAttrs lhs
      then mapAttrs (_: recurDefault) lhs
      else if isFunction lhs
      then { }
      else lhs;
    recur = lhs: rhs:
      if !(isAttrs rhs)
      then recurDefault lhs
      else if isFunction lhs
      then mapAttrs (name: recur (lhs name)) rhs
      else if isAttrs lhs
      then
        mapAttrs (name: lhs:
          if rhs ? ${name}
          then recur lhs rhs.${name}
          else recurDefault lhs)
        lhs
      else lhs;
  in
    recur;

  flattenAttrs = sep: let
    recur = acc: path: attrs:
      foldl' (
        acc: name: let
          path' = path ++ [ name ];
          value = attrs.${name};
        in
          if isAttrs value && value.type or null != "derivation" && value.recurseForDerivations or null != false
          then recur acc path' (removeAttrs value [ "recurseForDerivations" ])
          else acc // { ${concatStringsSep sep path'} = value; }
      )
      acc (attrNames attrs);
  in
    attrs: recur { } [ ] attrs;

  flattenInheritAttrs = flattenAttrs "_";

  extendsList = overlays: initial: fix (foldl' (flip extends) initial overlays);

  defaultUpdateExtend = defaultAttrs: attrs: updater: let
    prev = recursiveUpdate (applyAttrs defaultAttrs attrs) attrs;
    final = let rhs = updater final prev; in recursiveUpdate prev (applyAttrs rhs prev);
  in
    final;

  listNixTree = let
    recur = dir: listing:
      listToAttrs (concatMap (
        name: let
          path = dir + "/${name}";
        in
          if listing.${name} == "directory"
          then let
            listing = readDir path;
          in
            singleton {
              inherit name;
              value =
                if listing."default.nix" or null == "regular"
                then path
                else recur path listing;
            }
          else if hasSuffix ".nix" name
          then
            singleton {
              name = removeSuffix ".nix" name;
              value = path;
            }
          else [ ]
      ) (attrNames listing));
  in
    dir: recur dir (readDir dir);

  listAttrs = import ./listAttrs.nix { inherit nixcfg nixpkgs; };

  mkNixcfg = import ./mkNixcfg { inherit nixcfg nixpkgs; };
}
