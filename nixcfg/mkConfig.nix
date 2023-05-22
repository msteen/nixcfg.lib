{ lib }: config: let
  listedArgs = lib.listAttrs config.path ({
      lib."overlay.nix" = "libOverlay";
      pkgs."overlay.nix" = "overlay";
      overlays = "overlays";
      data = "data";
      ".sops.yaml" = "sopsConfig";
    }
    // lib.genAttrs lib.configurationTypes (type: {
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

  # overlays:
  #   # We only disallow passing a default overlay directly when it already exist on the file system.
  #     if overlays ? default && listedArgs ? overlay
  #     then throw "The overlay name 'default' is already reserved for the overlay defined in 'pkgs/overlay.nix'."
  #     else
  #       overlays
  #       // lib.optionalAttrs (listedArgs ? overlay) {
  #         # We need to import because overlays are not allowed to be passed as paths.
  #         # A nixpkgs overlay should always be a function in the form `final: prev: { ... }`.
  #         default = import listedArgs.overlay;
  #       };

  listedConfig = {
    # Overlays are not allowed to be paths, but expected to be a function.
    # See the overlays option for more details.
    overlays = lib.mapAttrs (_: import) listedArgs.overlays;
    lib.overlays = map import (lib.optionalAttr "libOverlay" listedArgs);

    # For data, we are only interested in the values, not the paths that declare them.
    data = lib.mapAttrs (_: import) listedArgs.data;

    nixosConfigurations = defaultFromListed "nixos" (toListed listedArgs.nixosConfigurations);
    containerConfigurations = defaultFromListed "container" (toListed listedArgs.containerConfigurations);

    # Home configurations have a different directory structure,
    # so we handle the listed files differently too.
    homeConfigurations = homeFromListed (toListed listedArgs.homeConfigurations);

    sopsConfig = listedArgs.sopsConfig or null;
  };

  mergedConfig =
    config
    // {
      overlays = listedConfig.overlays // config.overlays or { };
      lib = config.lib or { } // { overlays = listedConfig.lib.overlays ++ config.lib.overlays or [ ]; };
      data = listedConfig.data // config.data or { };
      nixosConfigurations =
        listedConfig.nixosConfigurations
        // lib.mapAttrs (
          name: configuration:
            if listedConfig.nixosConfigurations ? ${name}
            then configuration // { modules = listedConfig.nixosConfigurations.${name}.modules ++ configuration.modules or [ ]; }
            else configuration
        )
        config.nixosConfigurations or { };
      containerConfigurations =
        listedConfig.containerConfigurations
        // lib.mapAttrs (
          name: configuration:
            if listedConfig.containerConfigurations ? ${name}
            then configuration // { modules = listedConfig.containerConfigurations.${name}.modules ++ configuration.modules or [ ]; }
            else configuration
        )
        config.containerConfigurations or { };
      homeConfigurations =
        listedConfig.homeConfigurations
        // lib.mapAttrs (
          name: configuration:
            if listedConfig.homeConfigurations ? ${name}
            then
              configuration
              // {
                users =
                  listedConfig.homeConfigurations.${name}.users
                  // lib.mapAttrs (
                    username: user:
                      user // { modules = listedConfig.homeConfigurations.${name}.users.${username}.modules ++ user.modules or [ ]; }
                  )
                  configuration.users or { };
              }
            else configuration
        )
        config.homeConfigurations or { };
      inherit (listedConfig) sopsConfig;
    }
    // lib.getAttrs (lib.concatMap (type: [ "${type}Modules" "${type}Profiles" ]) lib.configurationTypes) listedArgs;
in
  (lib.evalModules {
    modules = [
      ../modules/nixcfg.nix
      {
        _file = (lib.unsafeGetAttrPos "name" config).file or null;
        config = mergedConfig;
      }
    ];
  })
  .config
