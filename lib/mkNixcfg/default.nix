{
  nixpkgs,
  nixcfg,
}: rawArgs: let
  inherit
    (builtins)
    attrNames
    attrValues
    catAttrs
    compareVersions
    concatMap
    elem
    elemAt
    filter
    getAttr
    groupBy
    head
    intersectAttrs
    isAttrs
    isList
    isString
    length
    listToAttrs
    mapAttrs
    split
    splitVersion
    toJSON
    ;
  inherit
    (nixpkgs.lib)
    concatStrings
    filterAttrs
    foldr
    getAttrs
    hasPrefix
    mapAttrs'
    mapAttrsToList
    nameValuePair
    optional
    optionalAttrs
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
    maximum
    optionalAttr
    optionalInherit
    traceJSONMap
    ;

  inherit (rawArgs.inputs) self;

  filterNixpkgsInputs = filterAttrs (
    name: _:
      elem name [ "nixpkgs" "nixpkgs-unstable" ]
      || hasPrefix "nixos-" name
      || hasPrefix "release-" name
  );

  withDefaultNixpkgs = nixpkgsAttrs: hasNixpkgs: fallbackNixpkgs: let
    latestNixpkgs =
      mapAttrs (_: names: nixpkgsAttrs.${maximum compareVersions names})
      (groupBy (name: head (splitVersion name)) (attrNames nixpkgsAttrs));
  in
    nixpkgsAttrs
    // optionalAttrs (!hasNixpkgs) {
      nixpkgs = latestNixpkgs.nixos or latestNixpkgs.release or fallbackNixpkgs;
    };

  systems = rawArgs.systems or [ "x86_64-linux" "aarch64-linux" ];

  nixcfgsData = import ./mkNixcfgs.nix { inherit nixcfg nixpkgs; } rawArgs.inputs;
  nixcfgs = nixcfgsData.list;
  nixcfgsInputs = concatAttrs (catAttrs "inputs" nixcfgs);
  nixcfgsNixpkgsInputs = withDefaultNixpkgs (filterNixpkgsInputs nixcfgsInputs) (nixcfgsInputs ? nixpkgs) nixpkgs;
  nixcfgsChannels = mkChannels nixcfgsNixpkgsInputs systems;
  nixcfgsLib = let
    channelName = rawArgs.lib.channelName or "nixpkgs";
    input =
      nixcfgsNixpkgsInputs.${channelName}
      or (throw "The lib nixpkgs channel '${channelName}' does not exist.");
  in
    extendsList (catAttrs "libOverlay" nixcfgs) (final:
      nixcfg.lib
      // {
        lib = input.lib // { inherit input; };
      });

  mkChannels = import ./mkChannels.nix {
    inherit nixpkgs;
    nixcfgsOverlays = mapAttrs (_: getAttr "overlays") nixcfgsData.attrs;
    channels = rawArgs.channels or { };
  };

  mkDefaultModules = type:
    concatMap attrValues (catAttrs "${type}Modules" nixcfgs)
    ++ concatMap (optionalAttr "base") (catAttrs "${type}Profiles" nixcfgs);

  mkSpecialArgs = {
    name,
    inputs,
    moduleArgs,
    ...
  }:
    {
      # We cannot inherit name, as it will conflict with the workings of submodules.
      # It would for example lead to misconfiguring home manager.
      inherit inputs;
      nixcfg = self;
      nixcfgs = nixcfgsData.attrs;
    }
    // moduleArgs;

  mkHomeModules = import ./mkHomeModules.nix {
    inherit mkDefaultModules nixcfgs nixpkgs requireSops;
  };

  mkNixosModules = import ./mkNixosModules.nix {
    inherit mkDefaultModules mkHomeModules mkSpecialArgs nixcfgs nixpkgs requireSops self;
    homeApplyArgs = applyArgs.home;
  };

  listedArgs = listAttrs rawArgs.path ({
      lib."overlay.nix" = "libOverlay";
      pkgs."overlay.nix" = "overlay";
      overlays = "overlays";
      data = "data";
      ".sops.yaml" = "sopsConfig";
    }
    // mapAttrs (name: _: {
      configs = "${name}Configurations";
      modules = "${name}Modules";
      profiles = "${name}Profiles";
    })
    types);

  requireSops = listedArgs ? sopsConfig;

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
        modules = let
          modules =
            prev.${name}.modules
            ++ optionalAttr name listedArgs.nixosConfigurations;
        in
          if modules == [ ]
          then throw "The nixos configuration '${name}' is missing in 'nixos/configs/'."
          else modules;
      };

      apply = args: (import (args.pkgs.input + "/nixos/lib/eval-config.nix") {
        inherit (args) lib system;
        specialArgs = mkSpecialArgs args;
        modules = mkNixosModules args;
      });
    };

    container = {
      default = _:
        default
        // {
          modules.nixos = [ ];
          modules.container = [ ];
        };

      fromListed = mapToAttrs ({
        name,
        nameParts,
        ...
      }:
        if length nameParts == 2 && elem (elemAt nameParts 1) [ "container" "nixos" ]
        then nameValuePair (head nameParts) { }
        else throw "The container configuration '${name}' should be in the root of 'container/configs/<name>' as '{container,nixos}.nix' or '{container,nixos}/default.nix'.");

      extend = final: prev: name: {
        modules.nixos = let
          modules =
            prev.${name}.modules.nixos
            ++ optionalAttr "${name}_nixos" listedArgs.containerConfigurations;
        in
          if modules == [ ]
          then throw "The container configuration '${name}' should be in the root of 'container/configs/<name>' as 'nixos.nix' or 'nixos/default.nix'."
          else modules;
        modules.container =
          prev.${name}.modules.container
          ++ optionalAttr "${name}_container" listedArgs.containerConfigurations;
      };

      requiredInputs = [ "extra-container" ];

      apply = {
        name,
        inputs,
        system,
        modules,
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
          config.containers.${name} = mkMerge (
            mkDefaultModules "container"
            ++ modules.container
            ++ singleton {
              specialArgs = mkSpecialArgs args;
              config = {
                imports =
                  mkNixosModules (args // { modules = modules.nixos; })
                  ++ optional (applyArgs.home ? ${name}) {
                    systemd.services.fix-home-manager = {
                      serviceConfig = {
                        Type = "oneshot";
                      };
                      script = concatStrings (mapAttrsToList (name: _: ''
                          mkdir -p /nix/var/nix/{profiles,gcroots}/per-user/${name}
                          chown ${name}:root /nix/var/nix/{profiles,gcroots}/per-user/${name}
                        '')
                        applyArgs.home.${name}.users);
                      wantedBy = [ "multi-user.target" ];
                    };
                  };
              };
            }
          );
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
            modules = let
              modules =
                prev.${name}.users.${username}.modules
                ++ optionalAttr "${name}_${username}" listedArgs.homeConfigurations;
            in
              if modules == [ ]
              then throw "The home configuration '${name}' is missing a user configuration for '${username}' in 'home/configs/${name}/'."
              else modules;
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
          nameValuePair "${name}_${username}" (inputs.home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            extraSpecialArgs = mkSpecialArgs args;
            modules = mkHomeModules args username user;
            check = true;
          }))
        users;
    };
  };

  configurationsArgs = let
    configurationsArgs = mapAttrs (type: configuration: let
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
    in
      mapAttrs (
        name: {
          system,
          channelName,
          ...
        } @ configurationArgs:
          if !(elem system systems)
          then throw "The ${type} configuration '${name}' has system '${system}', which is not listed in the supported systems."
          else configurationArgs
      )
      configurationsArgs)
    types;
  in (
    if intersectAttrs configurationsArgs.nixos configurationsArgs.container != { }
    then throw "The names of nixos and container configurations are not allowed to overlap. This would make it ambiguous to which a home configuration should be added."
    else configurationsArgs
  );

  applyArgs = mapAttrs (type: configurationsArgs:
    recursiveUpdate configurationsArgs (mapAttrs (
        name: {
          system,
          channelName,
          ...
        } @ configurationArgs: let
          inputs = nixcfgsInputs // rawArgs.inputs // configurationArgs.inputs;
          channels =
            withDefaultNixpkgs
            (recursiveUpdate (mkChannels (filterNixpkgsInputs inputs) [ system ]).${system} nixcfgsChannels.${system})
            (inputs ? nixpkgs)
            (mkChannels { inherit nixpkgs; } [ system ]).${system}.nixpkgs;
          pkgs = channels.${channelName} or (throw "The ${type} nixpkgs channel '${channelName}' does not exist.");
          unavailableInputs = filter (requiredInput: !(inputs ? ${requiredInput})) ((types.${type}.requiredInputs or [ ]) ++ optional requireSops "sops-nix");
        in
          if unavailableInputs != [ ]
          then throw "The ${type} configuration '${name}' did not specify '${head unavailableInputs}' as part of their inputs."
          else {
            inherit channels inputs name pkgs;
            inherit (pkgs) lib;
          }
      )
      configurationsArgs))
  configurationsArgs;

  configurations =
    mapAttrs (
      type: { apply ? (_: [ ]), ... }:
        mapAttrs (_: listToAttrs) (groupBy (x:
            x.value.system
            or x.value.pkgs.system
            or (throw "The ${type} configuration is missing a system or pkgs attribute."))
          (concatMapAttrsToList (name: args: let
            value = apply args;
          in
            if !(isList value)
            then singleton (nameValuePair name value)
            else value)
          applyArgs.${type}))
    )
    types;

  overlays = let
    overlays = mapAttrs (_: import) listedArgs.overlays // rawArgs.overlays or { };
  in
    if overlays ? default
    then throw "The overlay name 'default' is already reserved for the overlay defined in 'pkgs/overlay.nix'."
    else
      overlays
      // optionalAttrs (self ? overlay) {
        default = self.overlay;
      };
in
  {
    inherit nixcfgs overlays;
    inherit (rawArgs) inputs name;
    data = mapAttrs (_: import) listedArgs.data // rawArgs.data or { };
    outPath = rawArgs.path;
    lib = nixcfgsLib;
  }
  # Nixpkgs overlays are required to be overlay functions, paths are not allowed.
  // mapAttrs (_: import) (optionalInherit listedArgs [ "libOverlay" "overlay" ])
  // getAttrs (concatMap (type: [ "${type}Modules" "${type}Profiles" ]) (attrNames types)) listedArgs
  // mapAttrs' (type: nameValuePair "${type}ConfigurationsArgs") configurationsArgs
  // mapAttrs' (type: nameValuePair "${type}Configurations") configurations
