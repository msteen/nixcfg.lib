{
  self,
  lib,
}: {
  getAttrPath = lib.flip (lib.foldl' (lib.flip lib.getAttr));
  catAttrsPath = lib.flip (lib.foldl' (lib.flip lib.catAttrs));

  mapGetAttrPath = lib.flip (lib.foldl' (list: name: map (lib.getAttr name) list));

  concatAttrs = lib.foldl' (a: b: a // b) { };
  concatAttrsRecursive = lib.foldl' lib.recursiveUpdate { };

  concatMapAttrs' = f: attrs: lib.listToAttrs (lib.concatMap (name: f name attrs.${name}) (lib.attrNames attrs));
  concatMapAttrs = f: self.concatMapAttrs' (name: value: lib.nameValuePair name (f name value));

  mapToAttrs = f: list: lib.listToAttrs (map f list);
  concatMapToAttrs = f: list: lib.listToAttrs (lib.concatMap f list);

  concatMapAttrsToList = f: attrs: lib.concatLists (lib.mapAttrsToList f attrs);

  filterMapAttrs' = f: g: self.concatMapAttrs' (name: value: lib.optional (f name value) (g name value));
  filterMapAttrs = f: g: self.filterMapAttrs' f (name: value: lib.nameValuePair name (g name value));

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

  concatLevels = levels: lib.foldl' (self.updateLevels levels) { };

  optionalAttr = name: attrs:
    lib.optional (attrs ? ${name}) attrs.${name};

  optionalInherit = attrs: names:
    lib.listToAttrs (lib.concatMap (name:
      lib.optional (attrs ? ${name}) {
        inherit name;
        value = attrs.${name};
      })
    names);

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

  flattenInheritAttrs = self.flattenAttrs "_";

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
}
