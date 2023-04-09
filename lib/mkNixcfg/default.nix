{
  nixpkgs,
  nixcfg,
}: {
  name,
  path,
  inputs,
  ...
} @ rawArgs: let
  inherit (builtins) catAttrs filter head listToAttrs mapAttrs match toJSON;
  inherit (nixpkgs.lib) foldr mapAttrs' nameValuePair recursiveUpdate;
  inherit (nixcfg.lib) applyAttrs concatAttrs defaultUpdateExtend extendsList listAttrs optionalInherit;

  inherit (inputs) self;

  mkChannels = inputs: import ./mkChannels.nix { inherit nixpkgs; } inputs;

  nixcfgs = import ./mkNixcfgs.nix { inherit nixpkgs; } inputs;
  nixcfgsInputs = concatAttrs (catAttrs "inputs" nixcfgs);
  nixcfgsChannels = mkChannels nixcfgsInputs;
  nixcfgsLib = let
    channelName = rawArgs.lib.channelName or null;
    input =
      if channelName != null
      then
        inputs.${channelName}
        or (throw "The lib nixpkgs channel '${channelName}' does not exist.")
      else nixpkgs;
  in
    extendsList (catAttrs "libOverlay" nixcfgs) (final:
      nixcfg.lib
      // {
        lib = input.lib // { inherit input; };
      });

  mkSpecialArgs = {
    name,
    inputs,
    moduleArgs,
    ...
  }:
    {
      inherit inputs name;
      nixcfg = self;
      nixcfgs = listToAttrs (map (nixcfg: nameValuePair nixcfg.name nixcfg) nixcfgs);
    }
    // moduleArgs;

  mkNixosModules = import ./mkNixosModules.nix { inherit nixcfgs nixcfgsChannels nixpkgs self; };

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
    types);

  types = let
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
      apply = args: (import (args.pkgs.input + "/nixos/lib/eval-config.nix") {
        inherit (args) lib system;
        specialArgs = mkSpecialArgs args;
        modules = mkNixosModules args;
      });
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
      # apply = {
      #   name,
      #   inputs,
      #   system,
      #   channel,
      #   ...
      # } @ args:
      #   inputs.extra-container.lib.buildContainers {
      #     inherit system;
      #     nixpkgs = channel.input.outPath;
      #     # FXIME
      #     config.containers.${name} = { };
      #   };
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
        nixosConfigurationArgs = configurationsArgs.nixos.${name};
        homeConfigurationArgs = prev.${name};
        invalidOptions =
          filter (option: homeConfigurationArgs ? ${option} && homeConfigurationArgs.${option} != nixosConfigurationArgs.${option})
          [ "system" "channelName" "stateVersion" ];
      in
        if configurationsArgs.nixos ? ${name} && invalidOptions != [ ]
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
        };
      requiredInputs = [ "home-manager" ];
      # apply = {
      #   inputs,
      #   pkgs,
      #   ...
      # } @ args:
      #   import (inputs.home-manager + "/modules") {
      #     inherit pkgs;
      #     extraSpecialArgs = mkSpecialArgs args;
      #     check = true;
      #   };
    };
  };

  configurationsRawArgs = let
    firstName = name: head (match "^([[:alnum:]]+).*" name);
  in
    mapAttrs (type: configuration: let
      configurationsRawArgs =
        defaultUpdateExtend
        configuration.default or { }
        (mapAttrs' (name: _: nameValuePair (firstName name) { }) listedArgs."${type}Configurations"
          // rawArgs."${type}Configurations" or { })
        configuration.extend or (_: _: { });
    in
      mapAttrs (
        name: configurationRawArgs:
          foldr (
            requiredInput: accum: (
              if !(nixcfgsInputs ? ${requiredInput} || configurationRawArgs.inputs ? ${requiredInput})
              then throw "Host did not specify '${requiredInput}' as part of their inputs."
              else accum
            )
          )
          configurationRawArgs
          configuration.requiredInputs or [ ]
      )
      configurationsRawArgs)
    types;

  configurationsArgs = mapAttrs (_: configurationsRawArgs:
    recursiveUpdate configurationsRawArgs (mapAttrs (name: configurationRawArgs: let
        inputs = removeAttrs rawArgs.inputs [ "self" ] // configurationRawArgs.inputs;
        channels = recursiveUpdate nixcfgsChannels (mkChannels inputs);
        pkgs = channels.${configurationRawArgs.channelName};
      in {
        inherit inputs name pkgs;
        inherit (pkgs) lib;
      })
      configurationsRawArgs))
  configurationsRawArgs;

  configurations = mapAttrs (name: type:
    mapAttrs (_: args: (type.apply or (_: { }) args))
    configurationsArgs.${name})
  types;
in
  {
    inherit inputs name nixcfgs;
    outPath = path;
    lib = nixcfgsLib;
  }
  // mapAttrs' (name: nameValuePair "${name}ConfigurationsArgs") configurationsRawArgs
  // mapAttrs' (name: nameValuePair "${name}Configurations") configurations
  // mapAttrs (_: import) (optionalInherit listedArgs [ "libOverlay" "overlay" ])
