{
  nixpkgs,
  nixcfg,
}: {
  name,
  path,
  inputs,
  ...
} @ rawArgs: let
  inherit (builtins) mapAttrs;
  inherit (nixpkgs.lib) mapAttrs' nameValuePair;
  inherit (nixcfg.lib) defaultUpdateExtend listAttrs;

  nixcfgs = import ./nixcfgs.nix { inherit inputs nixpkgs; };

  listedArgs = listAttrs path ({
      lib."overlay.nix" = "libOverlay";
      pkgs."overlay.nix" = "overlay";
      overlays = "overlays";
      secrets = "secrets";
    }
    // mapAttrs (name: _: {
      configurations = "${name}Configurations";
      modules = "${name}Modules";
      profiles = "${name}Profiles";
    })
    configurations);

  configurations = let
    default = {
      inputs = { };
      channelName = "nixpkgs";
      system = "x86_64-linux";
      moduleArgs = { };
      stateVersion = "22.11";
    };
  in {
    nixos = {
      default = _: default // { modules = [ ]; };
      extend = final: prev: name: {
        modules =
          prev.${name}.modules
          ++ [
            listedArgs.nixosConfigurations.${name}
            or (abort
              "The nixos configuration '${name}' is missing in 'nixos/configurations/'.")
          ];
      };
    };
    container = {
      default = _: default // { modules = [ ]; };
      extend = final: prev: name: {
        modules =
          prev.${name}.modules
          ++ [
            listedArgs.containerConfigurations.${name}
            or (abort
              "The container configuration '${name}' is missing in 'container/configurations/'.")
          ];
      };
    };
    home = {
      default = _:
        default
        // {
          users = _: {
            modules = [ ];
          };
        };
      extend = final: prev: name: {
        users = username: {
          modules =
            prev.${name}.users.${username}.modules
            ++ [
              listedArgs.homeConfigurations."${name}_${username}"
              or (abort
                "The home configuration '${name}' is missing a user configuration for '${username}' in 'home/configurations/${name}/'.")
            ];
        };
      };
    };
  };

  args = mapAttrs (name: configuration:
    defaultUpdateExtend
    configuration.default or { }
    (mapAttrs (_: _: { }) listedArgs."${name}Configurations" // rawArgs."${name}Configurations" or { })
    configuration.extend or (_: _: { }))
  configurations;
in
  {
    inherit inputs name nixcfgs;
    outPath = path;
  }
  // mapAttrs' (name: nameValuePair "${name}ConfigurationArgs") args
