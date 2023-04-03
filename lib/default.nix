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
  concatAttrs = foldl' (a: b: a // b) { };
  concatAttrsRecursive = foldl' (a: b: recursiveUpdate a b) { };

  callableUpdate = let
    recur = callable: rhs:
      zipAttrsWith (_: values: let
        callable = elemAt values 1;
        value = head values;
      in
        if length values == 1
        then
          if isFunction value
          then { }
          else value
        else if !(isAttrs value)
        then value
        else recur callable value)
      (let
        lhs =
          if isFunction callable
          then
            if isAttrs rhs
            then mapAttrs (name: _: callable name) rhs
            else { }
          else callable;
      in [ rhs lhs ]);
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
    prev = recursiveUpdate defaultAttrs attrs;
    final = recursiveUpdate prev (updater final prev);
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
