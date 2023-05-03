{
  lib,
  nixpkgs,
  nixcfg,
}: {
  traceJSON = x: lib.trace (lib.toJSON x) x;
  traceJSONMap = f: x: lib.trace (lib.toJSON (f x)) x;
  traceJSONValue = value: lib.traceJSONMap (lib.const value);

  concatAttrs = lib.foldl' (a: b: a // b) { };
  concatAttrsRecursive = lib.foldl' (a: b: lib.recursiveUpdate a b) { };

  updateLevels = levels: lhs: rhs: let
    recur = levels:
      lib.zipAttrsWith (
        _: values:
          if levels == 0 || lib.length values == 1 || !(lib.isAttrs (lib.elemAt values 1) && lib.isAttrs (lib.head values))
          then lib.head values
          else recur (levels - 1) values
      );
  in
    recur levels [ rhs lhs ];

  concatMapAttrsToList = f: attrs: lib.concatLists (lib.mapAttrsToList f attrs);

  mapToAttrs = f: list: lib.listToAttrs (map f list);

  maximum = compare: list:
    lib.foldl' (a: b:
      if a == null || compare a b < 1
      then b
      else a)
    null
    list;

  optionalAttr = name: attrs:
    if attrs ? ${name}
    then [ attrs.${name} ]
    else [ ];

  optionalInherit = attrs: names:
    lib.listToAttrs (lib.concatMap (name:
      if attrs ? ${name}
      then [
        {
          inherit name;
          value = attrs.${name};
        }
      ]
      else [ ])
    names);

  attrsGetAttr = name: attrs:
    lib.listToAttrs (lib.concatMapAttrsToList (n: v:
      if v ? ${name}
      then [ (lib.nameValuePair n v.${name}) ]
      else [ ])
    attrs);

  applyAttrs = let
    recurDefault = lhs:
      if lib.isAttrs lhs
      then lib.mapAttrs (_: recurDefault) lhs
      else if lib.isFunction lhs
      then { }
      else lhs;
    recur = lhs: rhs:
      if !(lib.isAttrs rhs)
      then recurDefault lhs
      else if lib.isFunction lhs
      then lib.mapAttrs (name: recur (lhs name)) rhs
      else if lib.isAttrs lhs
      then
        lib.mapAttrs (name: lhs:
          if rhs ? ${name}
          then recur lhs rhs.${name}
          else recurDefault lhs)
        lhs
      else lhs;
  in
    recur;

  flattenAttrs = sep: let
    recur = acc: path: attrs:
      lib.foldl' (
        acc: name: let
          path' = path ++ [ name ];
          value = attrs.${name};
        in
          if lib.isAttrs value && value.type or null != "derivation" && value.recurseForDerivations or null != false
          then recur acc path' (removeAttrs value [ "recurseForDerivations" ])
          else acc // { ${lib.concatStringsSep sep path'} = value; }
      )
      acc (lib.attrNames attrs);
  in
    attrs: recur { } [ ] attrs;

  flattenInheritAttrs = lib.flattenAttrs "_";

  extendsList = overlays: initial: lib.fix (lib.foldl' (lib.flip lib.extends) initial overlays);

  defaultUpdateExtend = defaultAttrs: attrs: updater: let
    prev = lib.recursiveUpdate (lib.applyAttrs defaultAttrs attrs) attrs;
    final = let rhs = updater final prev; in lib.recursiveUpdate prev (lib.applyAttrs rhs prev);
  in
    final;

  listNixTree = let
    recur = dir: listing:
      lib.listToAttrs (lib.concatMap (
        name: let
          path = dir + "/${name}";
        in
          if listing.${name} == "directory"
          then let
            listing = lib.readDir path;
          in
            lib.singleton {
              inherit name;
              value =
                if listing."default.nix" or null == "regular"
                then path
                else recur path listing;
            }
          else if lib.hasSuffix ".nix" name
          then
            lib.singleton {
              name = lib.removeSuffix ".nix" name;
              value = path;
            }
          else [ ]
      ) (lib.attrNames listing));
  in
    dir: recur dir (lib.readDir dir);

  listAttrs = import ./listAttrs.nix { inherit lib; };

  mkNixcfg = import ./mkNixcfg { inherit lib nixcfg nixpkgs; };

  dummyNixosModule = {
    boot.loader.grub.enable = false;
    fileSystems."/".device = "/dev/null";
  };
}
