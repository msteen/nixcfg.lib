{ lib }: let
  nameToType = name:
    if lib.hasInfix "." name
    then "regular"
    else "directory";

  listAttrDefault = name: type:
    if type == "regular"
    then [ ]
    else
      lib.singleton {
        inherit name;
        value = { };
      };

  recurDefault = tree:
    lib.concatMap (
      name: let
        value = tree.${name};
      in
        if lib.isAttrs value
        then recurDefault value
        else listAttrDefault value (nameToType name)
    ) (lib.attrNames tree);
in
  path: tree: let
    recur = path: tree: let
      listing = lib.readDir path;
    in
      lib.concatMap (
        filename: let
          name = tree.${filename};
          treeType = nameToType filename;
          listedType = listing.${filename} or null;
          path' = path + "/${filename}";
        in
          if lib.isAttrs name
          then
            if listedType == "directory"
            then recur path' name
            else recurDefault name
          else if listedType == treeType
          then
            lib.singleton {
              inherit name;
              value =
                if listedType == "regular"
                then path'
                else lib.flattenInheritAttrs (lib.listNixTree path');
            }
          else listAttrDefault name treeType
      ) (lib.attrNames tree);
  in
    lib.listToAttrs (recur path tree)
