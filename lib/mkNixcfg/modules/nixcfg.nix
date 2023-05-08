{
  lib,
  config,
  nixcfg,
  ...
}: let
  inherit (lib) types;

  configurationTypes = [ "nixos" "container" "home" ];

  listedArgs = lib.listAttrs config.path ({
      lib."overlay.nix" = "libOverlay";
      pkgs."overlay.nix" = "overlay";
      overlays = "overlays";
      data = "data";
      ".sops.yaml" = "sopsConfig";
    }
    // lib.genAttrs configurationTypes (type: {
      configs = "${type}Configurations";
      modules = "${type}Modules";
      profiles = "${type}Profiles";
    }));
in {
  options = let
    # https://github.com/NixOS/nixpkgs/blob/1a411f23ba299db155a5b45d5e145b85a7aafc42/nixos/modules/misc/nixpkgs.nix#L45-L50
    overlay = lib.mkOptionType {
      name = "overlay";
      description = "overlay";
      check = lib.isFunction;
      merge = lib.mergeOneOption;
    };

    # The raw type won't try to merge.
    flake = types.raw;

    mkSubmoduleOptions = options: types.submodule { inherit options; };

    configurationOptions = {
      inputs = lib.mkOption {
        type = types.lazyAttrsOf flake;
        default = { };
      };
      channelName = lib.mkOption {
        type = types.str;
        default = "nixpkgs";
      };
      system = lib.mkOption {
        type = types.str;
        default = "x86_64-linux";
      };
      moduleArgs = lib.mkOption {
        type = types.lazyAttrsOf types.raw;
        default = { };
      };
      stateVersion = lib.mkOption {
        type = types.str;
        default = "22.11";
      };
    };

    modulesOptions = {
      modules = lib.mkOption {
        type = types.listOf types.raw;
        default = [ ];
      };
    };

    checkConfigurationSystem = type: name: configuration:
      if !(lib.elem configuration.system config.systems)
      then throw "The ${type} configuration '${name}' has system '${configuration.system}', which is not listed in the supported systems."
      else configuration;
  in
    {
      name = lib.mkOption {
        type = types.str;
        description = ''
          The name of the nixcfg. It is used when referring to this nixcfg.
        '';
      };
      path = lib.mkOption {
        type = types.path;
        description = ''
          The path where the nixcfg is located and from where arguments will be listed.
        '';
      };
      inputs = lib.mkOption {
        type = types.submodule {
          freeformType = types.lazyAttrsOf flake;
          options.self = lib.mkOption {
            type = flake;
          };
        };
        description = ''
          The flake inputs of the nixcfg. It is expected to contain at least the self input, i.e. the self-reference.
        '';
      };

      overlays = lib.mkOption {
        type = types.lazyAttrsOf overlay;
        default = { };
        apply = overlays:
          if overlays ? default
          then throw "The overlay name 'default' is already reserved for the overlay defined in 'pkgs/overlay.nix'."
          else
            overlays
            // lib.optionalAttrs (listedArgs ? overlay) {
              default = listedArgs.overlay;
            };
      };

      systems = lib.mkOption {
        type = types.listOf (types.enum nixcfg.inputs.flake-utils.lib.allSystems);
        default = [ "x86_64-linux" "aarch64-linux" ];
      };

      channels = lib.mkOption {
        type = types.lazyAttrsOf (mkSubmoduleOptions {
          input = lib.mkOption {
            type = types.nullOr flake;
            default = null;
          };
          config = lib.mkOption {
            type = types.attrs;
            default = { };
          };
          patches = lib.mkOption {
            type = types.listOf types.path;
            default = [ ];
          };
          overlays = lib.mkOption {
            type = types.either (types.listOf overlay) (types.functionTo (types.listOf overlay));
            default = [ ];
          };
        });
        default = { };
      };

      lib = lib.mkOption {
        type = mkSubmoduleOptions {
          inherit (configurationOptions) channelName;
          overlays = lib.mkOption {
            type = types.listOf overlay;
            default = [ ];
          };
        };
        default = { };
      };

      data = lib.mkOption {
        type = types.lazyAttrsOf types.raw;
        default = { };
      };

      nixosConfigurations = lib.mkOption {
        type = types.lazyAttrsOf (mkSubmoduleOptions (configurationOptions // modulesOptions));
        default = { };
        apply = lib.mapAttrs (name: configuration:
          if configuration.modules == [ ]
          then throw "The nixos configuration '${name}' is missing as configured modules or in 'nixos/configs/'."
          else checkConfigurationSystem "nixos" name configuration);
      };

      containerConfigurations = lib.mkOption {
        type = types.lazyAttrsOf (mkSubmoduleOptions (configurationOptions // modulesOptions));
        default = { };
        apply = configurations: let
          inherit (config) nixosConfigurations;
          containerConfigurations = lib.mapAttrs (name: configuration:
            if configuration.modules == [ ]
            then throw "The container configuration '${name}' is missing as configured modules or in 'container/configs/'."
            else checkConfigurationSystem "container" name configuration)
          configurations;
        in
          if lib.length (lib.attrNames (lib.intersectAttrs containerConfigurations nixosConfigurations)) != lib.length (lib.attrNames containerConfigurations)
          then throw "For each container configuration there should be a corresponding nixos configuration."
          else containerConfigurations;
      };

      homeConfigurations = lib.mkOption {
        type = types.lazyAttrsOf (mkSubmoduleOptions (
          configurationOptions
          // {
            users = lib.mkOption {
              type = types.lazyAttrsOf (types.submodule ({ name, ... }: {
                options =
                  modulesOptions
                  // {
                    homeDirectory = lib.mkOption {
                      type = types.path;
                      default = "/home/${name}";
                    };
                  };
              }));
              default = { };
            };
          }
        ));
        default = { };
        apply = lib.mapAttrs (name: homeConfiguration: let
          nixosConfiguration = config.nixosConfigurations.${name};
          invalidOptions =
            lib.filter (option: homeConfiguration ? ${option} && homeConfiguration.${option} != nixosConfiguration.${option})
            [ "system" "channelName" "stateVersion" ];
        in
          if config.nixosConfigurations ? ${name} && invalidOptions != [ ]
          then throw "The home configuration '${name}' has the options ${lib.toJSON invalidOptions} that do not equal those found in its NixOS configuration."
          else
            homeConfiguration
            // {
              users =
                lib.mapAttrs (
                  username: userConfiguration:
                    if userConfiguration.modules == [ ]
                    then throw "The home configuration '${name}' is missing a user configuration for '${username}' as configured modules or in 'home/configs/${name}/'."
                    else userConfiguration
                )
                homeConfiguration.users;
            });
      };

      sopsConfig = lib.mkOption {
        internal = true;
        type = types.nullOr types.path;
      };

      requireSops = lib.mkOption {
        internal = true;
        type = types.bool;
        default = config.sopsConfig != null;
      };
    }
    // lib.genAttrs (lib.concatMap (type: [ "${type}Modules" "${type}Profiles" ]) configurationTypes) (name:
      lib.mkOption {
        internal = true;
        type = types.attrsOf types.path;
        default = listedArgs.${name};
      });

  config = let
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
  in {
    lib.overlays = map import (lib.optionalAttr "libOverlay" listedArgs);
    overlays = lib.mapAttrs (_: import) listedArgs.overlays;
    data = lib.mapAttrs (_: import) listedArgs.data;
    sopsConfig = listedArgs.sopsConfig or null;
    nixosConfigurations = defaultFromListed "nixos" (toListed listedArgs.nixosConfigurations);
    containerConfigurations = defaultFromListed "container" (toListed listedArgs.containerConfigurations);
    homeConfigurations = homeFromListed (toListed listedArgs.homeConfigurations);
  };
}
