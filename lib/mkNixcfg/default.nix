{
  nixpkgs,
  nixcfg,
}: rawArgs: let
  inherit
    (builtins)
    attrNames
    attrValues
    catAttrs
    concatMap
    elem
    elemAt
    filter
    groupBy
    head
    isAttrs
    isList
    isString
    length
    listToAttrs
    mapAttrs
    split
    toJSON
    ;
  inherit
    (nixpkgs.lib)
    foldr
    getAttrs
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
    concatMapAttrsToList
    defaultUpdateExtend
    extendsList
    listAttrs
    mapToAttrs
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

  nixcfgsData = import ./mkNixcfgs.nix { inherit nixcfg nixpkgs; } rawArgs.inputs;
  nixcfgs = nixcfgsData.list;
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
      nixcfgs = nixcfgsData.attrs;
    }
    // moduleArgs;

  mkHomeModules = import ./mkHomeModules.nix {
    inherit nixcfgs nixpkgs;
  };

  mkNixosModules = import ./mkNixosModules.nix {
    inherit mkHomeModules mkSpecialArgs nixcfgs nixcfgsChannels nixcfgsInputs nixpkgs self;
    homeApplyArgs = applyArgs.home;
  };

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
            or (throw "The nixos configuration '${name}' is missing in 'nixos/configs/'.")
          ];
      };

      apply = args: (import (args.pkgs.input + "/nixos/lib/eval-config.nix") {
        inherit (args) lib system;
        specialArgs = mkSpecialArgs args;
        modules =
          concatMap attrValues (catAttrs "nixosModules" nixcfgs)
          ++ mkNixosModules args;
      });
    };

    container = {
      default = _: default // { modules = [ ]; };

      fromListed = mapToAttrs ({
        name,
        nameParts,
        ...
      }: let
        target = elemAt nameParts 1;
      in
        if length nameParts == 2 && elem target [ "container" "nixos" ]
        then nameValuePair (head nameParts) { }
        else throw "The container configuration '${name}' should be in the root of 'container/configs/<name>' as '{container,nixos}.nix' or '{container,nixos}/default.nix'.");

      extend = final: prev: name: {
        modules =
          prev.${name}.modules
          ++ [
            listedArgs.containerConfigurations."${name}_nixos"
            or (throw "The container configuration '${name}' is missing in 'container/configs/'.")
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
        (inputs.extra-container or nixcfgsInputs.extra-container).lib.buildContainers {
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
                imports =
                  concatMap attrValues (catAttrs "nixosModules" nixcfgs)
                  ++ concatMap attrValues (catAttrs "containerModules" nixcfgs)
                  ++ mkNixosModules args;
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
          users = username: {
            homeDirectory = "/home/${username}";
            modules = [ ];
          };
        };

      fromListed = listed:
        mapAttrs (_: group: {
          users = mapToAttrs ({ username, ... }: nameValuePair username { }) group;
        }) (groupBy (x: x.name) (map ({
          name,
          nameParts,
          ...
        }:
          if length nameParts == 2
          then {
            name = head nameParts;
            username = elemAt nameParts 1;
          }
          else throw "The home configuration '${name}' should be in the root of 'home/configs/<name>' as '<username>.nix' or '<username>/default.nix'.")
        listed));

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
                or (throw "The home configuration '${name}' is missing a user configuration for '${username}' in 'home/configs/${name}/'.")
              ];
          };
        };

      requiredInputs = [ "home-manager" ];

      apply = {
        name,
        inputs,
        pkgs,
        stateVersion,
        users,
        ...
      } @ args:
        mapAttrsToList (username: user:
          nameValuePair "${name}_${username}" ((inputs.home-manager or nixcfgsInputs.home-manager).lib.homeManagerConfiguration {
            inherit pkgs;
            extraSpecialArgs = mkSpecialArgs args;
            modules = mkHomeModules args username user;
            check = true;
          }))
        users;
    };
  };

  configurationsArgs = mapAttrs (type: configuration: let
    defaultFromListed = listed:
      mapToAttrs ({
        name,
        nameParts,
        ...
      }:
        if length nameParts == 1
        then nameValuePair (head nameParts) { }
        else throw "The ${type} configuration '${name}' should be in the root of '${type}/configs/' as '${name}.nix' or '${name}/default.nix'.")
      listed;

    configurationsArgs =
      defaultUpdateExtend
      configuration.default or { }
      ((configuration.fromListed or defaultFromListed) (mapAttrsToList (name: path: {
          inherit name path;
          nameParts = filter (x: isString x && x != "") (split "_" name);
        })
        listedArgs."${type}Configurations")
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
              if !(inputs ? ${requiredInput} || nixcfgsInputs ? ${requiredInput})
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
        mapAttrs (_: listToAttrs) (groupBy (x:
            x.value.system
            or x.value.pkgs.system
            or (throw "The ${type} configuration is missing a system or pkgs attribute."))
          (concatMapAttrsToList (name: args: let
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
    # Nixpkgs overlays are required to be overlay functions, paths are not allowed.
    overlays = mapAttrs (_: import) listedArgs.overlays;
  }
  // mapAttrs (_: import) (optionalInherit listedArgs [ "libOverlay" "overlay" ])
  // getAttrs (concatMap (type: [ "${type}Modules" "${type}Profiles" ]) (attrNames types)) listedArgs
  // mapAttrs' (type: nameValuePair "${type}ConfigurationsArgs") configurationsArgs
  // mapAttrs' (type: nameValuePair "${type}Configurations") configurations
