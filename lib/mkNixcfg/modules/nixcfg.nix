{
  lib,
  nixcfg,
}: { config, ... }: let
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
  _file = ./.;

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

    configurationOptions = type: {
      inputs = lib.mkOption {
        type = types.lazyAttrsOf flake;
        default = { };
        description = ''
          The flake inputs of this ${type} configuration.
          They extend those of the nixcfg.
        '';
      };
      channelName = lib.mkOption {
        type = types.str;
        default = "nixpkgs";
        description = ''
          The channel that should be used for this ${type} configuration.
        '';
      };
      system = lib.mkOption {
        type = types.str;
        default = "x86_64-linux";
        description = ''
          The system of this ${type} configuration.
        '';
      };
      moduleArgs = lib.mkOption {
        type = types.lazyAttrsOf types.raw;
        default = { };
        description = ''
          The list of arguments that should be passed to the module system evaluation for this ${type} configuration.
        '';
      };
      stateVersion = lib.mkOption {
        type = types.str;
        default = "22.11";
        description = ''
          The state version of this ${type} configuration.
          By default the latest stable nixos version is used.
        '';
      };
    };

    modulesOptions = type: {
      modules = lib.mkOption {
        type = types.listOf types.raw;
        default = [ ];
        description = ''
          The list of ${type} modules that represent this ${type} configuration.
          By default, if there exist a ${type} configuration file, it will be added to this list.
        '';
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
          The name used to refer to this nixcfg.
        '';
      };
      path = lib.mkOption {
        type = types.path;
        description = ''
          The path where this nixcfg is located and from where arguments will be listed.
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
          The flake inputs of this nixcfg.
          The self input, i.e. the self-reference, is expected to be available.
          It's metadata is used for setting various defaults.
        '';
      };

      overlays = lib.mkOption {
        type = types.lazyAttrsOf overlay;
        default = { };
        apply = overlays:
          if overlays ? default && listedArgs ? overlay
          then throw "The overlay name 'default' is already reserved for the overlay defined in 'pkgs/overlay.nix'."
          else
            overlays
            // lib.optionalAttrs (listedArgs ? overlay) {
              default = listedArgs.overlay;
            };
        description = ''
          The nixpkgs overlays that can be used to extend a nixpkgs channel.
          Only the default overlay, so named or defined in 'pkgs/overlays.nix',
          is added by default to the list of nixpkgs overlays.
        '';
      };

      systems = lib.mkOption {
        type = types.listOf (types.enum nixcfg.inputs.flake-utils.lib.allSystems);
        default = [ "x86_64-linux" "aarch64-linux" ];
        description = ''
          The list of systems that are supported.
          Any referenced system, e.g. in a nixos configuration, must be an element of this list.
        '';
      };

      channels = lib.mkOption {
        type = types.lazyAttrsOf (mkSubmoduleOptions {
          input = lib.mkOption {
            type = types.nullOr flake;
            default = null;
            description = ''
              The nixpkgs flake input that should be used for this channel.
            '';
          };
          config = lib.mkOption {
            type = types.attrs;
            default = { };
            description = ''
              The nixpkgs config that should be used for this channel.
              By default all channels allow unfree packages.
            '';
          };
          patches = lib.mkOption {
            type = types.listOf types.path;
            default = [ ];
            description = ''
              The list of patches that should be applied to the nixpkgs input of this channel.
            '';
          };
          overlays = lib.mkOption {
            type = types.either (types.listOf overlay) (types.functionTo (types.listOf overlay));
            default = [ ];
            description = ''
              The list of nixpkgs overlays that should be used for this channel.
            '';
          };
        });
        default = { };
        description = ''
          The set of nixpkgs channels made available for use in the configurations.
          They are made available as a nixpkgs overlay on the channel selected for the configuration.
        '';
      };

      lib = lib.mkOption {
        type = mkSubmoduleOptions {
          inherit (configurationOptions "lib") channelName;
          overlays = lib.mkOption {
            type = types.listOf overlay;
            default = [ ];
            description = ''
              The list of lib overlays that should be used for this lib.
            '';
          };
        };
        default = { };
        description = ''
          The extended lib made available as an output and passed to the module system.
        '';
      };

      data = lib.mkOption {
        type = types.lazyAttrsOf types.raw;
        default = { };
        description = ''
          Arbitrary Nix expressions that can be shared between configurations.
        '';
      };

      nixosConfigurations = lib.mkOption {
        type = types.lazyAttrsOf (mkSubmoduleOptions (configurationOptions "nixos" // modulesOptions "nixos"));
        default = { };
        apply = lib.mapAttrs (name: configuration:
          if configuration.modules == [ ]
          then throw "The nixos configuration '${name}' is missing as configured modules or in 'nixos/configs/'."
          else checkConfigurationSystem "nixos" name configuration);
        description = ''
          The set of nixos configurations.
          If a nixos configuration shares a name with a container configuration,
          it will be used for the container and not be made available seperately.
        '';
      };

      containerConfigurations = lib.mkOption {
        type = types.lazyAttrsOf (mkSubmoduleOptions (configurationOptions "container" // modulesOptions "container"));
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
        description = ''
          The set of container configurations.
          These are nixos containers, i.e. systemd containers.
        '';
      };

      homeConfigurations = lib.mkOption {
        type = types.lazyAttrsOf (mkSubmoduleOptions (
          configurationOptions "home"
          // {
            users = lib.mkOption {
              type = types.lazyAttrsOf (types.submodule ({ name, ... }: {
                options =
                  modulesOptions "home"
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
        description = ''
          The set of home configurations.
          If a home configuration shares a name with a nixos configuration,
          it will be embedded in the nixos configuration, yet will still be made available seperately.
        '';
      };

      sopsConfig = lib.mkOption {
        internal = true;
        type = types.nullOr types.path;
        description = ''
          The path to the SOPS config file, if available.
        '';
      };

      requireSops = lib.mkOption {
        internal = true;
        type = types.bool;
        default = config.sopsConfig != null;
        description = ''
          Whether SOPS support is required.
        '';
      };
    }
    // lib.mapToAttrs ({
      type,
      kind,
      name,
    }:
      lib.nameValuePair name (lib.mkOption {
        type = types.attrsOf types.path;
        default = { };
        description = ''
          The set of ${type} ${kind} made available in ${type} configurations.
        '';
      })) (lib.concatMap (type: [
        {
          inherit type;
          kind = "modules";
          name = "${type}Modules";
        }
        {
          inherit type;
          kind = "profiles";
          name = "${type}Profiles";
        }
      ])
      configurationTypes);

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
  in
    {
      lib.overlays = map import (lib.optionalAttr "libOverlay" listedArgs);
      overlays = lib.mapAttrs (_: import) listedArgs.overlays;
      data = lib.mapAttrs (_: import) listedArgs.data;
      sopsConfig = listedArgs.sopsConfig or null;
      nixosConfigurations = defaultFromListed "nixos" (toListed listedArgs.nixosConfigurations);
      containerConfigurations = defaultFromListed "container" (toListed listedArgs.containerConfigurations);
      homeConfigurations = homeFromListed (toListed listedArgs.homeConfigurations);
    }
    // lib.getAttrs (lib.concatMap (type: [ "${type}Modules" "${type}Profiles" ]) configurationTypes) listedArgs;
}
