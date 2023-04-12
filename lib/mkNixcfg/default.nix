{
  nixpkgs,
  nixcfg,
}: rawArgs: let
  inherit
    (builtins)
    catAttrs
    concatLists
    elem
    filter
    head
    isList
    listToAttrs
    mapAttrs
    match
    toJSON
    ;
  inherit
    (nixpkgs.lib)
    foldr
    mapAttrs'
    mapAttrsToList
    nameValuePair
    recursiveUpdate
    singleton
    ;
  inherit
    (nixcfg.lib)
    applyAttrs
    concatAttrs
    defaultUpdateExtend
    extendsList
    listAttrs
    optionalInherit
    ;

  inherit (rawArgs.inputs) self;

  mkChannels = inputs:
    import ./mkChannels.nix {
      inherit nixpkgs;
      channels = rawArgs.channels or { };
    }
    inputs;

  systems = rawArgs.systems or [ "x86_64-linux" "aarch64-linux" ];

  nixcfgs = import ./mkNixcfgs.nix { inherit nixpkgs; } rawArgs.inputs;
  nixcfgsInputs = concatAttrs (catAttrs "inputs" nixcfgs);
  nixcfgsChannels = mkChannels systems nixcfgsInputs;
  nixcfgsLib = let
    channelName = rawArgs.lib.channelName or null;
    input =
      if channelName != null
      then
        nixcfgsInputs.${channelName}
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

  listedArgs = listAttrs rawArgs.path ({
      lib."overlay.nix" = "libOverlay";
      pkgs."overlay.nix" = "overlay";
      overlays = "overlays";
      secrets = "secrets";
    }
    // mapAttrs (name: _: {
      configs = "${name}Configurations";
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
            listedArgs.containerConfigurations."${name}_nixos"
            or (throw
              "The container configuration '${name}' is missing in 'container/configurations/'.")
          ];
      };
      requiredInputs = [ "extra-container" ];
      apply = {
        name,
        inputs,
        system,
        channels,
        pkgs,
        lib,
        ...
      } @ args: let
        inherit (lib) mkMerge;
      in
        inputs.extra-container.lib.buildContainers {
          inherit system;
          # This potentially needs to be newer than the configured nixpkgs channel,
          # due to `specialArgs` support being a very recent addition to NixOS containers.
          # Rather than making it configurable seperately, we use the default behavior,
          # of it defaulting to the nixpkgs input of `extra-container`.
          # nixpkgs = pkgs.input;
          config.containers.${name} = mkMerge [
            {
              specialArgs = mkSpecialArgs args;
              config = {
                imports = mkNixosModules args;
              };
            }
            listedArgs.containerConfigurations."${name}_container" or { }
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
      extend = final: prev: name: let
        nixosConfigurationArgs = configurationsArgs.nixos.${name};
        homeConfigurationArgs = prev.${name};
        invalidOptions =
          filter (option: homeConfigurationArgs ? ${option} && homeConfigurationArgs.${option} != nixosConfigurationArgs.${option})
          [ "system" "channelName" "stateVersion" ];
      in
        if configurationsArgs.nixos ? ${name} && invalidOptions != [ ]
        then throw "The home configuration '${name}' has the options ${toJSON invalidOptions} that do not equal those found in its NixOS configuration."
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

  configurationsArgs = let
    firstName = name: head (match "^([[:alnum:]]+).*" name);
  in
    mapAttrs (type: configuration: let
      configurationsArgs =
        defaultUpdateExtend
        configuration.default or { }
        (mapAttrs' (name: _: nameValuePair (firstName name) { }) listedArgs."${type}Configurations"
          // rawArgs."${type}Configurations" or { })
        configuration.extend or (_: _: { });
    in
      mapAttrs (
        name: {
          inputs,
          system,
          channelName,
          ...
        } @ configurationArgs:
          if !(elem system systems)
          then throw "The ${type} configuration '${name}' has system '${system}', which is not listed in the supported systems."
          else
            foldr (
              requiredInput: accum: (
                if !(nixcfgsInputs ? ${requiredInput} || inputs ? ${requiredInput})
                then throw "The ${type} configuration '${name}' did not specify '${requiredInput}' as part of their inputs."
                else accum
              )
            )
            configurationArgs
            configuration.requiredInputs or [ ]
      )
      configurationsArgs)
    types;

  applyArgs = mapAttrs (_: configurationsArgs:
    recursiveUpdate configurationsArgs (mapAttrs (name: configurationArgs: let
        inherit (configurationArgs) system;
        inputs = removeAttrs rawArgs.inputs [ "self" ] // configurationArgs.inputs;
        channels = recursiveUpdate nixcfgsChannels.${system} (mkChannels [ system ] inputs).${system};
        pkgs = channels.${configurationArgs.channelName};
      in {
        inherit channels inputs name pkgs;
        inherit (pkgs) lib;
      })
      configurationsArgs))
  configurationsArgs;

  configurations =
    mapAttrs (
      name: type:
        listToAttrs (concatLists (mapAttrsToList (name: args: let
          value = type.apply or (_: [ ]) args;
        in
          if !(isList value)
          then singleton (nameValuePair name value)
          else value)
        applyArgs.${name}))
    )
    types;
in
  {
    inherit (rawArgs) inputs name;
    inherit nixcfgs;
    outPath = rawArgs.path;
    lib = nixcfgsLib;
  }
  // mapAttrs' (name: nameValuePair "${name}ConfigurationsArgs") configurationsArgs
  // mapAttrs' (name: nameValuePair "${name}Configurations") configurations
  // mapAttrs (_: import) (optionalInherit listedArgs [ "libOverlay" "overlay" ])
