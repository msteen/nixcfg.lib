{
  nixpkgs,
  nixcfg,
}: {
  name,
  path,
  inputs,
  ...
} @ rawArgs: let
  inherit (builtins) catAttrs filter head mapAttrs match toJSON;
  inherit (nixpkgs.lib) foldr mapAttrs' nameValuePair optionalAttrs;
  inherit (nixcfg.lib) concatAttrs defaultUpdateExtend listAttrs;

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
            or (throw
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
            or (throw
              "The container configuration '${name}' is missing in 'container/configurations/'.")
          ];
      };
      requiredInputs = [ "extra-container" ];
    };
    home = {
      default = _:
        default
        // {
          users = _: {
            modules = [ ];
          };
        };
      extend = final: prev: name: let
        nixosConfigurationArgs = args.nixos.${name};
        homeConfigurationArgs = prev.${name};
        invalidOptions =
          filter (option: homeConfigurationArgs ? ${option} && homeConfigurationArgs.${option} != nixosConfigurationArgs.${option})
          [ "system" "channelName" "stateVersion" ];
      in (
        if args.nixos ? ${name} && invalidOptions != [ ]
        then throw "The home configuration of '${name}' has the options ${toJSON invalidOptions} that do not equal those found in its NixOS configuration."
        else {
          users = username: {
            modules =
              prev.${name}.users.${username}.modules
              ++ [
                listedArgs.homeConfigurations."${name}_${username}"
                or (throw
                  "The home configuration '${name}' is missing a user configuration for '${username}' in 'home/configurations/${name}/'.")
              ];
          };
        }
      );
      requiredInputs = [ "home-manager" ];
    };
  };

  nixcfgsInputs = concatAttrs (catAttrs "inputs" nixcfgs);

  args = let
    firstName = name: head (match "^([[:alnum:]]+).*" name);
  in
    mapAttrs (type: configuration: let
      args =
        defaultUpdateExtend
        configuration.default or { }
        (mapAttrs' (name: _: nameValuePair (firstName name) { }) listedArgs."${type}Configurations"
          // rawArgs."${type}Configurations" or { })
        configuration.extend or (_: _: { });
    in
      mapAttrs (
        name: args:
          foldr (
            requiredInput: accum: (
              if !(nixcfgsInputs ? ${requiredInput} || args.inputs ? ${requiredInput})
              then throw "Host did not specify '${requiredInput}' as part of their inputs."
              else accum
            )
          )
          args
          configuration.requiredInputs or [ ]
      )
      args)
    configurations;
in
  {
    inherit inputs name nixcfgs;
    outPath = path;
  }
  // mapAttrs' (name: nameValuePair "${name}ConfigurationsArgs") args
