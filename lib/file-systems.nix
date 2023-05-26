{
  self,
  lib,
}: {
  readFileType =
    builtins.readFileType
    or (path:
      (builtins.readDir (dirOf path)).${baseNameOf path}
      or (throw "getting status of '${toString path}': No such file or directory"));

  listNix = dir: let
    f = name: type: let
      path =
        dir
        + (
          if type == "directory"
          then "/${name}/default.nix"
          else "/${name}"
        );
    in
      if type == "directory" && lib.pathExists path
      then lib.singleton (lib.nameValuePair name path)
      else if type == "regular"
      then
        lib.optional (lib.hasSuffix ".nix" name)
        (lib.nameValuePair (lib.removeSuffix ".nix" name) path)
      else [ ];
  in
    removeAttrs (self.concatMapAttrs' f (lib.readDir dir)) [ "default" ];

  listNixTree = let
    recur = dir: listing:
      self.concatMapAttrs' (
        name: type: let
          path = dir + "/${name}";
        in
          if type == "directory"
          then let
            listing = lib.readDir path;
          in
            lib.singleton (lib.nameValuePair name (
              if listing."default.nix" or null == "regular"
              then path
              else recur path listing
            ))
          else if type == "regular"
          then
            lib.optional (lib.hasSuffix ".nix" name)
            (lib.nameValuePair (lib.removeSuffix ".nix" name) path)
          else [ ]
      )
      listing;
  in
    dir: removeAttrs (recur dir (lib.readDir dir)) [ "default" ];

  listAttrs = let
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
      self.concatMapAttrsToList (
        name: value:
          if lib.isAttrs value
          then recurDefault value
          else listAttrDefault value (nameToType name)
      )
      tree;
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
                  else self.flattenInheritAttrs (self.listNixTree path');
              }
            else listAttrDefault name treeType
        ) (lib.attrNames tree);
    in
      lib.listToAttrs (recur path tree);
}
