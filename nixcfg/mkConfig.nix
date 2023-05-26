{ lib }: modules: let
  constants = import ./constants.nix;

  configPath = let
    paths = lib.filter (x: x != null) (map (x: x.path or x.config.path or null) modules);
  in
    if paths == [ ]
    then throw "None of the nixcfg modules have defined a path."
    else if !(lib.all lib.isPathLike paths)
    then
      throw "Some of the nixcfg modules have a path defined that is not path-like."
      + " They should all be convertable to paths, as despite being defined as part of a module,"
      + " it is being used before evaluating the modules to determine the listed config."
      + " Not doing so would require an additional evaluation of the modules."
    else lib.last paths;

  listedArgs = lib.listAttrs configPath ({
      lib."overlay.nix" = "libOverlay";
      pkgs."overlay.nix" = "overlay";
      overlays = "overlays";
      data = "data";
      ".sops.yaml" = "sopsConfig";
    }
    // lib.genAttrs constants.configurationTypes (type: {
      configs = "${type}Configurations";
      modules = "${type}Modules";
      profiles = "${type}Profiles";
    }));

  toListed = lib.mapAttrsToList (name: path: {
    inherit name path;
    nameParts = lib.filter (x: lib.isString x && x != "") (lib.split "_" name);
  });

  defaultFromListed = type: listed:
    lib.mapToAttrs ({
      name,
      nameParts,
      path,
      ...
    }:
      if lib.length nameParts == 1
      then
        lib.nameValuePair (lib.head nameParts) {
          modules = [ path ];
        }
      else throw "The ${type} configuration '${name}' should be in the root of '${type}/configs/' as '${name}.nix' or '${name}/default.nix'.")
    listed;

  homeFromListed = listed:
    lib.mapAttrs (_: group: {
      users = lib.mapToAttrs ({
        username,
        path,
        ...
      }:
        lib.nameValuePair username {
          modules = [ path ];
        })
      group;
    }) (lib.groupBy (x: x.name) (map ({
      name,
      nameParts,
      path,
      ...
    }:
      if lib.length nameParts == 2
      then {
        name = lib.head nameParts;
        username = lib.elemAt nameParts 1;
        inherit path;
      }
      else throw "The home configuration '${name}' should be in the root of 'home/configs/<name>' as '<username>.nix' or '<username>/default.nix'.")
    listed));

  listedConfig =
    {
      lib.overlays = map import (lib.optionalAttr "libOverlay" listedArgs);

      # For data, we are only interested in the values, not the paths that declare them.
      data = lib.mapAttrs (_: import) listedArgs.data;

      nixosConfigurations = defaultFromListed "nixos" (toListed listedArgs.nixosConfigurations);
      containerConfigurations = defaultFromListed "container" (toListed listedArgs.containerConfigurations);

      # Home configurations have a different directory structure,
      # so we handle the listed files differently too.
      homeConfigurations = homeFromListed (toListed listedArgs.homeConfigurations);

      sopsConfig = listedArgs.sopsConfig or null;
    }
    // lib.getAttrs (lib.concatMap (type: [ "${type}Modules" "${type}Profiles" ]) constants.configurationTypes) listedArgs;

  inherit (import ./mkModule.nix { inherit lib; }) firstPassModule secondPassModule;

  firstPassConfig = lib.evalModulesToConfig ([
      firstPassModule
      {
        _file = ./mkConfig.nix;
        config = listedConfig;
      }
    ]
    ++ map (x:
      if !x ? _file
      then x // { _file = configPath; }
      else x)
    modules);

  secondPassConfig = lib.evalModulesToConfig [
    secondPassModule
    {
      _file = configPath;
      config = lib.mkMerge [
        {
          overlays =
            # We only disallow passing a default overlay directly when it already exist on the file system.
            if firstPassConfig.overlays ? default && listedArgs ? overlay
            then throw "The overlay name 'default' is already reserved for the overlay defined in 'pkgs/overlay.nix'."
            else
              # Overlays are not allowed to be paths, but expected to be a function.
              # See the overlays option for more details.
              lib.mapAttrs (_: import) listedArgs.overlays
              // lib.optionalAttrs (listedArgs ? overlay) {
                # We need to import because overlays are not allowed to be passed as paths.
                # A nixpkgs overlay should always be a function in the form `final: prev: { ... }`.
                default = import listedArgs.overlay;
              };
        }
        (removeAttrs firstPassConfig [ "apply" ])
        (lib.mapAttrs (name: f: lib.applyAttrs f firstPassConfig.${name}) firstPassConfig.apply)
      ];
    }
  ];
in
  secondPassConfig // { requireSops = secondPassConfig.sopsConfig != null; }
