{
  lib,
  nixcfg,
  sources,
  alejandraOverlay,
}: {
  traceJSON = x: lib.trace (lib.toJSON x) x;
  traceJSONMap = f: x: lib.trace (lib.toJSON (f x)) x;
  traceJSONValue = value: x: lib.trace (lib.toJSON value) x;

  readFileType =
    builtins.readFileType
    or (path:
      (builtins.readDir (dirOf path)).${baseNameOf path}
      or throw "getting status of '${toString path}': No such file or directory");

  concatStringsEnglish = sep: list: let
    listLength = lib.length list;
    lastIndex = listLength - 1;
  in
    if listLength == 0
    then ""
    else if listLength == 1
    then lib.head list
    else if listLength == 2
    then "${lib.head list} ${sep} ${lib.elemAt list 1}"
    else lib.concatStringsSep ", " (lib.sublist 0 lastIndex list ++ [ "${sep} ${lib.elemAt list lastIndex}" ]);
  concatStringsAnd = lib.concatStringsEnglish "and";
  concatNames = list: lib.concatStringsAnd (map (name: "'${name}'") list);

  concatAttrs = lib.foldl' (a: b: a // b) { };
  concatAttrsRecursive = lib.foldl' (a: b: lib.recursiveUpdate a b) { };

  catAttrsPath = lib.flip (lib.foldl' (lib.flip lib.catAttrs));
  getAttrPath = lib.flip (lib.foldl' (lib.flip lib.getAttr));
  mapGetAttrPath = lib.flip (lib.foldl' (list: name: map (lib.getAttr name) list));

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

  filterMapAttrs = f: g: attrs:
    lib.listToAttrs (lib.concatMap (name: let
      value = attrs.${name};
    in
      lib.optional (f name value) (g name value)) (lib.attrNames attrs));

  maximum = compare: list:
    lib.foldl' (a: b:
      if a == null || compare a b < 1
      then b
      else a)
    null
    list;

  sort' = list: lib.sort (a: b: a < b) list;

  optionalAttr = name: attrs:
    lib.optional (attrs ? ${name}) attrs.${name};

  optionalInherit = attrs: names:
    lib.listToAttrs (lib.concatMap (name:
      lib.optional (attrs ? ${name}) {
        inherit name;
        value = attrs.${name};
      })
    names);

  attrsGetAttr = name: attrs:
    lib.listToAttrs (lib.concatMapAttrsToList (n: v:
      lib.optional (v ? ${name}) (lib.nameValuePair n v.${name}))
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
            lib.singleton (lib.nameValuePair name (
              if listing."default.nix" or null == "regular"
              then path
              else recur path listing
            ))
          else lib.optional (lib.hasSuffix ".nix" name) (lib.nameValuePair (lib.removeSuffix ".nix" name) path)
      ) (lib.attrNames listing));
  in
    dir: recur dir (lib.readDir dir);

  listAttrs = import ./listAttrs.nix { inherit lib; };

  flakeCompat = let
    lock = lib.fromJSON (lib.readFile (nixcfg.outPath + "/flake.lock"));
  in
    import (lib.fetchTarball {
      url = "https://github.com/edolstra/flake-compat/archive/${lock.nodes.flake-compat.locked.rev}.tar.gz";
      sha256 = lock.nodes.flake-compat.locked.narHash;
    });

  importFlake = path: (lib.flakeCompat { src = path; }).defaultNix;

  filterNixcfgSources = sources:
    lib.filterMapAttrs (name: _: lib.hasPrefix "nixcfg-" name)
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

  mkNixcfg = config: let
    self = import ./mkNixcfg { inherit alejandraOverlay lib nixcfg sources; } self config;
  in
    self;

  mkNixcfgFlake = config: let
    nixcfgInputs = lib.filterNixcfgSources config.inputs;
    nixcfg = lib.mkNixcfg ({
        path = config.inputs.self.outPath;
        sources = lib.mkSources config.inputs;
      }
      // removeAttrs config [ "inputs" ]
      // {
        nixcfgs =
          (lib.deduplicateNixcfgs (lib.concatMap (x:
              if x ? nixcfg
              then x.nixcfg.nixcfgs
              else [ x ])
            (map (x:
              if lib.isString x
              then nixcfgInputs.${x} or x
              else x)
            config.nixcfgs or [ ])))
          .list;
      });
    configurationTypes = lib.attrNames nixcfg.configurations;
    self =
      {
        inherit nixcfg;
        packages = let
          list = lib.concatMapAttrsToList (type:
            lib.mapAttrsToList (name: value: let
              configuration = nixcfg.configurations.${type}.${name};
              system =
                configuration.system
                or configuration.pkgs.system
                or (throw "The ${type} configuration is missing a system or pkgs attribute.");
            in { inherit name system type value; }))
          nixcfg.packages;
        in
          lib.mapAttrs (_: group:
            lib.mapAttrs (_:
              lib.listToAttrs)
            (lib.groupBy (x: x.type) group))
          (lib.groupBy (x: x.system) list);
        inherit (config) overlays;
        formatter =
          lib.genAttrs config.systems (system:
            self.legacyPackages.${system}.alejandra);
        legacyPackages = lib.mapAttrs (_: x: x.nixpkgs) nixcfg.channels;
      }
      // lib.mapAttrs' (type: lib.nameValuePair "${type}Configurations") nixcfg.configurations
      // lib.getAttrs (lib.concatMap (type: [ "${type}Modules" "${type}Profiles" ]) configurationTypes) config;
  in
    self;

  mkSources = inputs: lib.mapAttrs (_: input: input.outPath) (removeAttrs inputs [ "self" ]);

  dummyNixosModule = {
    boot.loader.grub.enable = false;
    fileSystems."/".device = "/dev/null";
  };

  fetchPullRequest = id: sha256:
    lib.fetchurl {
      url = "https://github.com/NixOS/nixpkgs/pull/${toString id}.diff";
      inherit sha256;
    };
}
