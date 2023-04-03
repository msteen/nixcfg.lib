{
  nixpkgs,
  nixcfg,
}: let
  inherit (builtins) attrNames concatMap isAttrs listToAttrs readDir;
  inherit (nixpkgs.lib) hasSuffix singleton;
  inherit (nixcfg.lib) flattenInheritAttrs listNixTree;

  nameToType = name:
    if hasSuffix ".nix" name
    then "regular"
    else "directory";

  listAttrDefault = name: type:
    if type == "regular"
    then [ ]
    else
      singleton {
        inherit name;
        value = { };
      };

  recurDefault = tree:
    concatMap (
      name: let
        value = tree.${name};
      in
        if isAttrs value
        then recurDefault value
        else listAttrDefault value (nameToType name)
    ) (attrNames tree);
in
  path: tree: let
    recur = path: tree: let
      listing = readDir path;
    in
      concatMap (
        filename: let
          name = tree.${filename};
          treeType = nameToType filename;
          listedType = listing.${filename} or null;
          path' = path + "/${filename}";
        in
          if isAttrs name
          then
            if listedType == "directory"
            then recur path' name
            else recurDefault name
          else if listedType == treeType
          then
            singleton {
              inherit name;
              value =
                if listedType == "regular"
                then path'
                else flattenInheritAttrs (listNixTree path');
            }
          else listAttrDefault name treeType
      ) (attrNames tree);
  in
    listToAttrs (recur path tree)
