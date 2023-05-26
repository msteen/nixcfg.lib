{ lib }: let
  constants = import ./constants.nix;

  inherit (lib) types;

  # There is no overlay type in the nixpkgs lib, so we have to define one ourselves.
  # Based on: https://github.com/NixOS/nixpkgs/blob/1a411f23ba299db155a5b45d5e145b85a7aafc42/nixos/modules/misc/nixpkgs.nix#L45-L50
  overlay = lib.mkOptionType {
    name = "overlay";
    description = "overlay";
    check = lib.isFunction;
    merge = lib.mergeOneOption;
  };

  nixcfg = types.attrs;

  configurationOptions = mkOption: type: {
    sources = mkOption {
      type = types.attrsOf types.path;
      default = { };
      description = ''
        The sources of this ${type} configuration. They extend those of the nixcfg.
      '';
    };

    channelName = mkOption {
      type = types.str;
      default = "nixpkgs";
      description = ''
        The channel that should be used for this ${type} configuration.
      '';
    };

    system = mkOption {
      type = types.str;
      default = "x86_64-linux";
      description = ''
        The system of this ${type} configuration.
      '';
    };

    moduleArgs = mkOption {
      type = types.attrsOf types.raw;
      default = { };
      description = ''
        The list of arguments that should be passed to the module system evaluation for this ${type} configuration.
      '';
    };

    stateVersion = mkOption {
      type = types.str;
      default = "22.11";
      description = ''
        The state version of this ${type} configuration.

        By default the latest stable nixos version is used.
      '';
    };
  };

  modulesOptions = mkOption: type: {
    modules = mkOption {
      type = types.listOf types.raw;
      default = [ ];
      description = ''
        The list of ${type} modules that represent this ${type} configuration.

        By default, if there exist a ${type} configuration file, it will be added to this list.
      '';
    };
  };

  mkSimpleConfigurationsOption = {
    mkOption,
    namedSubmodule,
    config,
  }: type: args: let
    default = {
      type = namedSubmodule (configurationOptions mkOption type // modulesOptions mkOption type);
      default = { };
      apply = lib.mapAttrs (name: configuration:
        if configuration.modules == [ ]
        then throw "The ${type} configuration '${name}' is missing as configured modules or in '${type}/configs/'."
        else if !(lib.elem configuration.system config.systems)
        then throw "The ${type} configuration '${name}' has system '${configuration.system}', which is not listed in the supported systems."
        else configuration);
    };
  in
    mkOption (
      default
      // args
      // lib.optionalAttrs (args ? apply) {
        apply = configurations: args.apply (default.apply configurations);
      }
    );

  toplevelOptions = {
    mkOption ? lib.mkOption,
    namedSubmodule ? options: types.attrsOf (lib.optionsToSubmodule options),
    config,
  }:
    {
      name = mkOption {
        type = types.str;
        description = ''
          The name used to refer to this nixcfg.
        '';
      };

      path = mkOption {
        type = types.path;
        description = ''
          The path where this nixcfg is located and from where arguments will be listed.
        '';
      };

      sources = mkOption {
        type = types.attrsOf types.path;
        description = ''
          The sources of this nixcfg.
        '';
      };

      nixcfgs = mkOption {
        type = types.listOf (types.either types.str nixcfg);
        default = [ ];
        description = ''
          The list of nixcfgs to be merged with this one in the order listed.
          These can be nixcfg names referring to their source, or actual nixcfgs.

          The sources cannot be used to determine this, because attrsets are unordered,
          yet the order is significant in how things will be merged.
        '';
      };

      overlays = mkOption {
        type = types.attrsOf overlay;
        default = { };
        description = ''
          The nixpkgs overlays that can be used to extend a nixpkgs channel.

          Only the default overlay, so named or defined in 'pkgs/overlays.nix',
          is added by default to the list of nixpkgs overlays.
        '';
      };

      systems = mkOption {
        type = types.listOf (types.enum (lib.sort' lib.platforms.all));
        default = [ "x86_64-linux" "aarch64-linux" ];
        description = ''
          The list of systems that are supported.
          Any referenced system, e.g. in a nixos configuration, must be an element of this list.
        '';
      };

      channels = mkOption {
        type = namedSubmodule {
          source = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = ''
              The nixpkgs source that should be used for this channel.
            '';
          };
          config = mkOption {
            type = types.attrs;
            default = { };
            description = ''
              The nixpkgs config that should be used for this channel.

              By default all channels allow unfree packages.
            '';
          };
          patches = mkOption {
            type = types.listOf types.path;
            default = [ ];
            description = ''
              The list of patches that should be applied to the nixpkgs source of this channel.
            '';
          };
          overlays = mkOption {
            type = types.either (types.listOf overlay) (types.functionTo (types.listOf overlay));
            default = [ ];
            description = ''
              The list of nixpkgs overlays that should be used for this channel.
            '';
          };
        };
        default = { };
        description = ''
          The set of nixpkgs channels made available for use in the configurations.
          They are made available as a nixpkgs overlay on the channel selected for the configuration.
        '';
      };

      lib = mkOption {
        type = lib.optionsToSubmodule {
          inherit (configurationOptions mkOption "lib") channelName;
          overlays = mkOption {
            type = types.listOf overlay;
            default = [ ];
            apply = overlays:
              if lib.any (overlay: lib.attrNames (lib.functionArgs overlay) != [ "lib" "self" ]) overlays
              then throw "Some of the lib overlays do not contain functions in the form of `{ self, lib }: { ... }`."
              else overlays;
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

      data = mkOption {
        # We want it to merge values where possible, which requires the unspecified type.
        type = types.attrsOf types.unspecified;
        default = { };
        description = ''
          Arbitrary Nix expressions that can be shared between configurations.
        '';
      };

      nixosConfigurations = mkSimpleConfigurationsOption { inherit config mkOption namedSubmodule; } "nixos" {
        description = ''
          The set of nixos configurations.
          If a nixos configuration shares a name with a container configuration,
          it will be used for the container and not be made available seperately.
        '';
      };

      containerConfigurations = mkSimpleConfigurationsOption { inherit config mkOption namedSubmodule; } "container" {
        apply = containerConfigurations: let
          inherit (config) nixosConfigurations;
        in
          if lib.length (lib.attrNames (lib.intersectAttrs containerConfigurations nixosConfigurations)) != lib.length (lib.attrNames containerConfigurations)
          then throw "For each container configuration there should be a corresponding nixos configuration."
          else containerConfigurations;
        description = ''
          The set of container configurations.
          These are nixos containers, i.e. systemd containers.
        '';
      };

      homeConfigurations = mkOption {
        type = namedSubmodule (
          configurationOptions mkOption "home"
          // {
            users = mkOption {
              type = namedSubmodule (name:
                modulesOptions mkOption "home"
                // {
                  homeDirectory = mkOption {
                    type = types.path;
                    default = "/home/${name}";
                    description = ''
                      The home directory of this user.
                    '';
                  };
                });
              default = { };
              description = ''
                The set of users available in this home configuration.
              '';
            };
          }
        );
        default = { };
        apply = lib.mapAttrs (name: homeConfiguration: let
          nixosConfiguration = config.nixosConfigurations.${name};
          invalidOptions =
            lib.filter (option: homeConfiguration ? ${option} && homeConfiguration.${option} != nixosConfiguration.${option})
            [ "system" "channelName" "stateVersion" ];
        in
          if config.nixosConfigurations ? ${name} && invalidOptions != [ ]
          then throw "The home configuration '${name}' has the options ${lib.concatNames invalidOptions} that do not equal those found in its NixOS configuration."
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

      sopsConfig = mkOption {
        internal = true;
        readOnly = true;
        type = types.nullOr types.path;
        description = ''
          The path to the SOPS config file, if available.
        '';
      };
    }
    // lib.mapToAttrs ({
      type,
      kind,
      name,
    }:
      lib.nameValuePair name (mkOption {
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
      constants.configurationTypes);

  mkOptionWithoutApply = config: lib.mkOption (removeAttrs config [ "apply" ]);

  topleveNamedModuleOptions = config:
    lib.filterMapAttrs (_: option: option.type.name == "functionTo")
    (_: option: option // { default = lib.const { }; })
    (toplevelOptions {
      mkOption = mkOptionWithoutApply;
      # TODO: See if we can still type valid values.
      # This could potentially be done by wrapping everything in `nullOr`,
      # setting `null` to be the default, and filtering `null` and `{ }` recursively.
      # Another potential way is using `options.<name>.isDefined` and `removeAttrs` on `config`,
      # such that the values are never evaluated.
      namedSubmodule = options: types.functionTo types.attrs;
      inherit config;
    });
in {
  firstPassModule = { config, ... }: {
    _file = ./mkModule.nix;
    options =
      toplevelOptions {
        mkOption = mkOptionWithoutApply;
        inherit config;
      }
      // {
        apply = lib.mkOption {
          type = lib.optionsToSubmodule (topleveNamedModuleOptions config);
          default = { };
          description = ''
            Apply a function over the result of merging the explicit and listed config.
            This allows you to map a function over the merged config rather than just the explicit config.
            Allowing you to e.g. add a module to every nixos configuration.
          '';
        };
      };
  };

  secondPassModule = { config, ... }: {
    _file = ./mkModule.nix;
    options = toplevelOptions { inherit config; };
  };
}
