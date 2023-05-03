{
  nixpkgs,
  nixcfg,
}: rawNixcfgArgs: let
  nixcfgArgs =
    {
      overlays = { };
      systems = [ "x86_64-linux" "aarch64-linux" ];
      channels = { };
      lib = { };
    }
    // rawNixcfgArgs;

  inherit (builtins)
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
    isFunction
    isList
    isString
    length
    listToAttrs
    mapAttrs
    split
    splitVersion
    toJSON
    ;
  inherit (nixpkgs.lib)
    concatStrings
    filterAttrs
    foldr
    genAttrs
    getAttrs
    hasPrefix
    mapAttrs'
    mapAttrsToList
    nameValuePair
    optional
    optionalAttrs
    singleton
    ;
  inherit (nixcfg.lib)
    applyAttrs
    attrsGetAttr
    concatAttrs
    concatMapAttrsToList
    defaultUpdateExtend
    extendsList
    listAttrs
    mapToAttrs
    maximum
    optionalAttr
    optionalInherit
    updateLevels
    ;

  flakeSystemAttrs = genAttrs [
    "checks"
    "packages"
    "packages"
    "apps"
    "formatter"
    "legacyPackages"
    "nixosConfigurations"
    "containerConfigurations"
    "homeConfigurations"
    "devShells"
  ] (_: null);

  inherit (nixcfgArgs.inputs) self;

  filterNixpkgsInputs = filterAttrs (
    name: _:
      elem name [ "nixpkgs" "nixpkgs-unstable" ]
      || hasPrefix "nixos-" name
      || hasPrefix "release-" name
  );

  inputsWithDefaultNixpkgs = inputs: let
    latestInputs =
      mapAttrs (_: names: inputs.${maximum compareVersions names})
      (groupBy (name: head (splitVersion name)) (attrNames inputs));
  in
    inputs
    // optionalAttrs (!inputs ? nixpkgs) {
      nixpkgs = latestInputs.nixos or latestInputs.release or nixpkgs;
    };

  nixcfgsData = import ./mkNixcfgs.nix { inherit nixcfg nixpkgs; } nixcfgArgs.inputs;
  nixcfgs = nixcfgsData.list;
  nixcfgsInputs = concatAttrs (catAttrs "inputs" nixcfgs);
  nixcfgsNixpkgsInputs = inputsWithDefaultNixpkgs (filterNixpkgsInputs nixcfgsInputs);
  nixcfgsChannels = mkChannels nixcfgsNixpkgsInputs nixcfgArgs.systems;
  nixcfgsLib = extendsList (catAttrs "libOverlay" nixcfgs) (final: nixcfg.lib);

  libNixpkgs = let
    channelName = nixcfgArgs.lib.channelName or "nixpkgs";
  in
    nixcfgsNixpkgsInputs.${channelName}
    or (throw "The lib nixpkgs channel '${channelName}' does not exist.");
  lib = nixcfgsLib // libNixpkgs.lib // builtins;

  mkChannels = import ./mkChannels.nix {
    inherit nixpkgs;
    nixcfgsOverlays = mapAttrs (_: getAttr "overlays") nixcfgsData.attrs;
    channels = nixcfgArgs.channels or { };
  };

  mkDefaultModules = type: name:
    concatMap attrValues (catAttrs "${type}Modules" nixcfgs)
    ++ concatMap (optionalAttr "base") (catAttrs "${type}Profiles" nixcfgs)
    ++ optional (requireSops && elem type [ "nixos" "home" ]) {
      sops.defaultSopsFile = self.outPath + "/${type}/configs/${name}/secrets.yaml";
    };

  mkSpecialArgs = type: {
    name,
    inputs',
    moduleArgs,
    ...
  }:
    {
      # We cannot inherit name, as it will conflict with the workings of submodules.
      # It would for example lead to misconfiguring home manager.
      inherit inputs';
      nixcfg = {
        inherit (nixcfgArgs) name;
        lib = nixcfgsLib;
      };
      data = mapAttrs (_: getAttr "data") nixcfgsData.attrs;
      profiles = mapAttrs (_: getAttr "${type}Profiles") nixcfgsData.attrs;
    }
    # Home Manager extends NixOS's lib, which we would overwrite with our own lib.
    // optionalAttrs (!(type == "home" && applyArgs.nixos ? ${name})) {
      inherit lib;
    }
    // moduleArgs;

  mkNixosModules = import ./mkNixosModules.nix {
    inherit mkDefaultModules mkHomeModules mkSpecialArgs nixcfgs nixpkgs requireSops self;
    homeApplyArgs = applyArgs.home;
  };

  mkHomeModules = import ./mkHomeModules.nix {
    inherit mkDefaultModules nixcfgs nixpkgs requireSops;
  };

  listedArgs = listAttrs nixcfgArgs.path ({
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
        specialArgs = mkSpecialArgs "nixos" args;
        modules = mkNixosModules args;
      });
    };

    container = {
      default = _: default // { modules = [ ]; };

      extend = final: prev: name: {
        modules = let
          modules =
            prev.${name}.modules
            ++ optionalAttr name listedArgs.containerConfigurations;
        in
          if modules == [ ]
          then throw "The container configuration '${name}' is missing in 'container/configs/'."
          else modules;
      };

      requiredInputs = [ "extra-container" ];

      apply = {
        name,
        inputs,
        system,
        channelName,
        modules,
        lib,
        ...
      } @ args: let
        inherit (lib) mkMerge mkOption;
        inherit (lib.types) attrsOf submoduleWith;
      in
        inputs.extra-container.lib.buildContainers {
          inherit system;
          nixpkgs = inputs.${channelName};
          config.imports =
            optional (compareVersions lib.trivial.release "23.05" < 0) (let
              nixpkgs =
                inputs.nixos-23_05
                or inputs.nixos-unstable
                or (throw ("To have similar module arguments within containers as in nixos we need special argument support."
                    + " This support has only be added in nixpkgs 23.05, so the nixpkgs channel 'nixos-23_05' or 'nixos-unstable' is required."));
            in {
              disabledModules = [ "virtualisation/nixos-containers.nix" ];
              imports = [ (nixpkgs.outPath + "/nixos/modules/virtualisation/nixos-containers.nix") ];
            })
            ++ singleton {
              options.containers = mkOption {
                type = attrsOf (submoduleWith {
                  shorthandOnlyDefinesConfig = true;
                  modules =
                    mkDefaultModules "container" name
                    ++ modules;
                  specialArgs = mkSpecialArgs "container" args;
                });
              };
              config.containers.${name} = let
                args = applyArgs.nixos.${name};
              in {
                specialArgs = mkSpecialArgs "nixos" args;
                config.imports =
                  mkNixosModules args
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
            };
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
            extraSpecialArgs = mkSpecialArgs "home" args;
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
        // nixcfgArgs."${type}Configurations" or { })
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
          if !(elem system nixcfgArgs.systems)
          then throw "The ${type} configuration '${name}' has system '${system}', which is not listed in the supported systems."
          else configurationArgs
      )
      configurationsArgs)
    types;
  in (
    if length (attrNames (intersectAttrs configurationsArgs.container configurationsArgs.nixos)) != length (attrNames configurationsArgs.container)
    then throw "For each container configuration there should be a corresponding nixos configuration."
    else configurationsArgs
  );

  applyArgs = mapAttrs (type: configurationsArgs:
    updateLevels 1 configurationsArgs (mapAttrs (
        name: {
          system,
          channelName,
          ...
        } @ configurationArgs: let
          inputs = inputsWithDefaultNixpkgs (nixcfgsInputs // nixcfgArgs.inputs // configurationArgs.inputs);
          inputs' = mapAttrs (_: flake: flake // attrsGetAttr system (intersectAttrs flakeSystemAttrs flake)) inputs;
          channels = (mkChannels (filterNixpkgsInputs inputs) [ system ]).${system} // nixcfgsChannels.${system};
          pkgs = channels.${channelName} or (throw "The ${type} nixpkgs channel '${channelName}' does not exist.");
          unavailableInputs = filter (requiredInput: !inputs ? ${requiredInput}) ((types.${type}.requiredInputs or [ ]) ++ optional requireSops "sops-nix");
        in
          if unavailableInputs != [ ]
          then throw "The ${type} configuration '${name}' did not specify '${head unavailableInputs}' as part of their inputs."
          else {
            inherit channels inputs inputs' name pkgs;
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
            (
              if type == "nixos"
              then removeAttrs applyArgs.nixos (attrNames applyArgs.container)
              else applyArgs.${type}
            )))
    )
    types;

  overlays = let
    overlays = mapAttrs (_: import) listedArgs.overlays // nixcfgArgs.overlays or { };
  in
    if overlays ? default
    then throw "The overlay name 'default' is already reserved for the overlay defined in 'pkgs/overlay.nix'."
    else
      overlays
      // optionalAttrs (listedArgs ? overlay) {
        default = listedArgs.overlay;
      };

  overlayOutputs = let
    # Nixpkgs overlays are required to be overlay functions, paths are not allowed.
    overlayOutputs = mapAttrs (_: import) (optionalInherit listedArgs [ "libOverlay" "overlay" ]);
    nixpkgsLibOverlay = { lib = libNixpkgs.lib // { input = libNixpkgs; }; };
  in
    overlayOutputs
    // optionalAttrs (overlayOutputs ? libOverlay) {
      libOverlay = let
        inherit (overlayOutputs) libOverlay;
      in
        if isFunction libOverlay
        then final: prev: libOverlay final prev // nixpkgsLibOverlay
        else libOverlay // nixpkgsLibOverlay;
    };
in
  {
    inherit lib nixcfgs overlays;
    inherit (nixcfgArgs) inputs name;
    data = mapAttrs (_: import) listedArgs.data // nixcfgArgs.data or { };
    outPath = nixcfgArgs.path;
    formatter = genAttrs nixcfgArgs.systems (system: nixcfg.inputs.alejandra.defaultPackage.${system});
  }
  // overlayOutputs
  // getAttrs (concatMap (type: [ "${type}Modules" "${type}Profiles" ]) (attrNames types)) listedArgs
  // mapAttrs' (type: nameValuePair "${type}ConfigurationsArgs") configurationsArgs
  // mapAttrs' (type: nameValuePair "${type}Configurations") configurations
