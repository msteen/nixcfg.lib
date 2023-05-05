{
  lib,
  nixpkgs,
  nixcfg,
}: config: let
  nixcfgModule = { lib, ... }: {
    options = let
      inherit (lib.types)
        attrs
        either
        enum
        functionTo
        lazyAttrsOf
        listOf
        nullOr
        path
        raw
        str
        submodule
        unspecified
        ;

      # https://github.com/NixOS/nixpkgs/blob/1a411f23ba299db155a5b45d5e145b85a7aafc42/nixos/modules/misc/nixpkgs.nix#L45-L50
      overlay = lib.mkOptionType {
        name = "nixpkgs-overlay";
        description = "nixpkgs overlay";
        check = lib.isFunction;
        merge = lib.mergeOneOption;
      };

      # The raw type won't try to merge.
      flake = raw;

      mkSubmoduleOptions = options: submodule { inherit options; };

      configurationOptions = {
        inputs = lib.mkOption {
          type = lazyAttrsOf flake;
          default = { };
        };
        channelName = lib.mkOption {
          type = str;
          default = "nixpkgs";
        };
        system = lib.mkOption {
          type = str;
          default = "x86_64-linux";
        };
        moduleArgs = lib.mkOption {
          type = lazyAttrsOf raw;
          default = { };
        };
        stateVersion = lib.mkOption {
          type = str;
          default = "22.11";
        };
      };

      modulesOptions = {
        modules = lib.mkOption {
          type = listOf unspecified;
          default = [ ];
        };
      };
    in {
      name = lib.mkOption {
        type = str;
      };
      path = lib.mkOption {
        type = path;
      };
      inputs = lib.mkOption {
        type = submodule {
          freeformType = lazyAttrsOf flake;
          options.self = lib.mkOption {
            type = flake;
          };
        };
      };
      overlays = lib.mkOption {
        type = lazyAttrsOf overlay;
        default = { };
      };
      systems = lib.mkOption {
        type = listOf (enum nixcfg.inputs.flake-utils.lib.allSystems);
        default = [ "x86_64-linux" "aarch64-linux" ];
      };
      channels = lib.mkOption {
        type = lazyAttrsOf (mkSubmoduleOptions {
          input = lib.mkOption {
            type = nullOr flake;
            default = null;
          };
          config = lib.mkOption {
            type = attrs;
            default = { };
          };
          patches = lib.mkOption {
            type = listOf path;
            default = [ ];
          };
          overlays = lib.mkOption {
            type = either (listOf overlay) (functionTo (listOf overlay));
            default = [ ];
          };
        });
        default = { };
      };
      lib = lib.mkOption {
        type = mkSubmoduleOptions {
          inherit (configurationOptions) channelName;
        };
        default = { };
      };
      nixosConfigurations = lib.mkOption {
        type = lazyAttrsOf (mkSubmoduleOptions (configurationOptions // modulesOptions));
        default = { };
      };
      containerConfigurations = lib.mkOption {
        type = lazyAttrsOf (mkSubmoduleOptions (configurationOptions // modulesOptions));
        default = { };
      };
      homeConfigurations = lib.mkOption {
        type = lazyAttrsOf (mkSubmoduleOptions (configurationOptions
          // {
            users = lib.mkOption {
              type = lazyAttrsOf (mkSubmoduleOptions ({ name }:
                modulesOptions
                // {
                  homeDirectory = lib.mkOption {
                    type = path;
                    default = "/home/${name}";
                  };
                }));
              default = { };
            };
          }));
        default = { };
      };
    };
  };
in
  (lib.evalModules {
    modules = [
      nixcfgModule
      {
        _file = (lib.unsafeGetAttrPos "name" config).file or null;
        inherit config;
      }
    ];
  })
  .config
