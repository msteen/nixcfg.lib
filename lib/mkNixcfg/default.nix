{
  lib,
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

  flakeSystemAttrs = lib.genAttrs [
    "checks"
    "packages"
    "packages"
    "apps"
    "formatter"
    "legacyPackages"
    "devShells"
  ] (_: null);

  inherit (nixcfgArgs.inputs) self;

  filterNixpkgsInputs = lib.filterAttrs (
    name: _:
      lib.elem name [ "nixpkgs" "nixpkgs-unstable" ]
      || lib.hasPrefix "nixos-" name
      || lib.hasPrefix "release-" name
  );

  inputsWithDefaultNixpkgs = inputs: let
    latestInputs =
      lib.mapAttrs (_: names: inputs.${lib.maximum lib.compareVersions names})
      (lib.groupBy (name: lib.head (lib.splitVersion name)) (lib.attrNames inputs));
  in
    inputs
    // lib.optionalAttrs (!inputs ? nixpkgs) {
      nixpkgs = latestInputs.nixos or latestInputs.release or nixpkgs;
    };

  nixcfgsData = import ./mkNixcfgs.nix { inherit lib; } nixcfgArgs.inputs;
  nixcfgs = nixcfgsData.list;
  nixcfgsInputs = lib.concatAttrs (lib.catAttrs "inputs" nixcfgs);
  nixcfgsNixpkgsInputs = inputsWithDefaultNixpkgs (filterNixpkgsInputs nixcfgsInputs);
  nixcfgsChannels = mkChannels nixcfgsNixpkgsInputs nixcfgArgs.systems;
  nixcfgsLib = lib.extendsList (lib.catAttrs "libOverlay" nixcfgs) (final: nixcfg.lib);

  libNixpkgs = let
    channelName = nixcfgArgs.lib.channelName or "nixpkgs";
  in
    nixcfgsNixpkgsInputs.${channelName}
    or (throw "The lib nixpkgs channel '${channelName}' does not exist.");

  outputLib = nixcfgsLib // libNixpkgs.lib // builtins;

  mkChannels = import ./mkChannels.nix {
    inherit lib;
    nixcfgsOverlays = lib.mapAttrs (_: lib.getAttr "overlays") nixcfgsData.attrs;
    channels = nixcfgArgs.channels or { };
  };

  mkDefaultModules = type: name:
    lib.concatMap lib.attrValues (lib.catAttrs "${type}Modules" nixcfgs)
    ++ lib.concatMap (lib.optionalAttr "base") (lib.catAttrs "${type}Profiles" nixcfgs)
    ++ lib.optional (requireSops && lib.elem type [ "nixos" "home" ]) {
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
      data = lib.mapAttrs (_: lib.getAttr "data") nixcfgsData.attrs;
      profiles = lib.mapAttrs (_: lib.getAttr "${type}Profiles") nixcfgsData.attrs;
    }
    # Home Manager extends NixOS's lib, which we would overwrite with our own lib.
    // lib.optionalAttrs (!(type == "home" && applyArgs.nixos ? ${name})) {
      lib = outputLib;
    }
    // moduleArgs;

  mkNixosModules = import ./mkNixosModules.nix {
    inherit lib mkDefaultModules mkHomeModules mkSpecialArgs nixcfgs requireSops self;
    homeApplyArgs = applyArgs.home;
  };

  mkHomeModules = import ./mkHomeModules.nix {
    inherit lib mkDefaultModules nixcfgs requireSops;
  };

  listedArgs = lib.listAttrs nixcfgArgs.path ({
      lib."overlay.nix" = "libOverlay";
      pkgs."overlay.nix" = "overlay";
      overlays = "overlays";
      data = "data";
      ".sops.yaml" = "sopsConfig";
    }
    // lib.mapAttrs (name: _: {
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
            ++ lib.optionalAttr name listedArgs.nixosConfigurations;
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
            ++ lib.optionalAttr name listedArgs.containerConfigurations;
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
        ...
      } @ args: let
        inherit (lib.types) attrsOf submoduleWith;
      in
        inputs.extra-container.lib.buildContainers {
          inherit system;
          nixpkgs = inputs.${channelName};
          config.imports =
            lib.optional (lib.compareVersions lib.trivial.release "23.05" < 0) (let
              nixpkgs =
                inputs.nixos-23_05
                or inputs.nixos-unstable
                or (throw ("To have similar module arguments within containers as in nixos we need special argument support."
                    + " This support has only be added in nixpkgs 23.05, so the nixpkgs channel 'nixos-23_05' or 'nixos-unstable' is required."));
            in {
              disabledModules = [ "virtualisation/nixos-containers.nix" ];
              imports = [ (nixpkgs.outPath + "/nixos/modules/virtualisation/nixos-containers.nix") ];
            })
            ++ lib.singleton {
              options.containers = lib.mkOption {
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
                  ++ lib.optional (applyArgs.home ? ${name}) {
                    systemd.services.fix-home-manager = {
                      serviceConfig = {
                        Type = "oneshot";
                      };
                      script = lib.concatStrings (lib.mapAttrsToList (name: _: ''
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
        lib.mapAttrs (_: group: {
          users = lib.mapToAttrs ({ username, ... }: lib.nameValuePair username { }) group;
        }) (lib.groupBy (x: x.name) (map ({
          name,
          nameParts,
          ...
        }:
          if lib.length nameParts == 2
          then {
            name = lib.head nameParts;
            username = lib.elemAt nameParts 1;
          }
          else throw "The home configuration '${name}' should be in the root of 'home/configs/<name>' as '<username>.nix' or '<username>/default.nix'.")
        listed));

      extend = final: prev: name: let
        nixosConfigurationArgs = configurationsArgs.nixos.${name};
        homeConfigurationArgs = prev.${name};
        invalidOptions =
          lib.filter (option: homeConfigurationArgs ? ${option} && homeConfigurationArgs.${option} != nixosConfigurationArgs.${option})
          [ "system" "channelName" "stateVersion" ];
      in
        if configurationsArgs.nixos ? ${name} && invalidOptions != [ ]
        then throw "The home configuration '${name}' has the options ${lib.toJSON invalidOptions} that do not equal those found in its NixOS configuration."
        else {
          users = username: {
            modules = let
              modules =
                prev.${name}.users.${username}.modules
                ++ lib.optionalAttr "${name}_${username}" listedArgs.homeConfigurations;
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
        lib.mapAttrsToList (username: user:
          lib.nameValuePair "${name}_${username}" (inputs.home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            extraSpecialArgs = mkSpecialArgs "home" args;
            modules = mkHomeModules args username user;
            check = true;
          }))
        users;
    };
  };

  configurationsArgs = let
    configurationsArgs = lib.mapAttrs (type: configuration: let
      configurationsArgs =
        lib.defaultUpdateExtend
        configuration.default or { }
        ((configuration.fromListed or defaultFromListed) (lib.mapAttrsToList (name: path: {
            inherit name path;
            nameParts = lib.filter (x: lib.isString x && x != "") (lib.split "_" name);
          })
          listedArgs."${type}Configurations")
        // nixcfgArgs."${type}Configurations" or { })
        configuration.extend or (_: _: { });

      defaultFromListed = listed:
        lib.mapToAttrs ({
          name,
          nameParts,
          ...
        }:
          if lib.length nameParts == 1
          then lib.nameValuePair (lib.head nameParts) { }
          else throw "The ${type} configuration '${name}' should be in the root of '${type}/configs/' as '${name}.nix' or '${name}/default.nix'.")
        listed;
    in
      lib.mapAttrs (
        name: {
          system,
          channelName,
          ...
        } @ configurationArgs:
          if !(lib.elem system nixcfgArgs.systems)
          then throw "The ${type} configuration '${name}' has system '${system}', which is not listed in the supported systems."
          else configurationArgs
      )
      configurationsArgs)
    types;
  in (
    if lib.length (lib.attrNames (lib.intersectAttrs configurationsArgs.container configurationsArgs.nixos)) != lib.length (lib.attrNames configurationsArgs.container)
    then throw "For each container configuration there should be a corresponding nixos configuration."
    else configurationsArgs
  );

  applyArgs = lib.mapAttrs (type: configurationsArgs:
    lib.updateLevels 1 configurationsArgs (lib.mapAttrs (
        name: {
          system,
          channelName,
          ...
        } @ configurationArgs: let
          inputs = inputsWithDefaultNixpkgs (nixcfgsInputs // nixcfgArgs.inputs // configurationArgs.inputs);
          inputs' = lib.mapAttrs (_: flake: flake // lib.attrsGetAttr system (lib.intersectAttrs flakeSystemAttrs flake)) inputs;
          channels = (mkChannels (filterNixpkgsInputs inputs) [ system ]).${system} // nixcfgsChannels.${system};
          pkgs = channels.${channelName} or (throw "The ${type} nixpkgs channel '${channelName}' does not exist.");
          unavailableInputs = lib.filter (requiredInput: !inputs ? ${requiredInput}) ((types.${type}.requiredInputs or [ ]) ++ lib.optional requireSops "sops-nix");
        in
          if unavailableInputs != [ ]
          then throw "The ${type} configuration '${name}' did not specify '${lib.head unavailableInputs}' as part of their inputs."
          else {
            inherit channels inputs inputs' name pkgs;
            inherit (pkgs) lib;
          }
      )
      configurationsArgs))
  configurationsArgs;

  configurations =
    lib.mapAttrs (
      type: { apply ? (_: [ ]), ... }:
        lib.listToAttrs (lib.concatMapAttrsToList (name: args: let
            value = apply args;
          in
            if !(lib.isList value)
            then lib.singleton (lib.nameValuePair name value)
            else value)
          (
            if type == "nixos"
            then removeAttrs applyArgs.nixos (lib.attrNames applyArgs.container)
            else applyArgs.${type}
          ))
    )
    types;

  overlays = let
    overlays = lib.mapAttrs (_: import) listedArgs.overlays // nixcfgArgs.overlays or { };
  in
    if overlays ? default
    then throw "The overlay name 'default' is already reserved for the overlay defined in 'pkgs/overlay.nix'."
    else
      overlays
      // lib.optionalAttrs (listedArgs ? overlay) {
        default = listedArgs.overlay;
      };

  overlayOutputs = let
    # Nixpkgs overlays are required to be overlay functions, paths are not allowed.
    overlayOutputs = lib.mapAttrs (_: import) (lib.optionalInherit listedArgs [ "libOverlay" "overlay" ]);
    nixpkgsLibOverlay = { lib = libNixpkgs.lib // { input = libNixpkgs; }; };
  in
    overlayOutputs
    // lib.optionalAttrs (overlayOutputs ? libOverlay) {
      libOverlay = let
        inherit (overlayOutputs) libOverlay;
      in
        if lib.isFunction libOverlay
        then final: prev: libOverlay final prev // nixpkgsLibOverlay
        else libOverlay // nixpkgsLibOverlay;
    };
in
  {
    inherit nixcfgs overlays;
    inherit (nixcfgArgs) inputs name;
    lib = outputLib;
    data = lib.mapAttrs (_: import) listedArgs.data // nixcfgArgs.data or { };
    outPath = nixcfgArgs.path;
    formatter = lib.genAttrs nixcfgArgs.systems (system: nixcfg.inputs.alejandra.defaultPackage.${system});
  }
  // overlayOutputs
  // lib.getAttrs (lib.concatMap (type: [ "${type}Modules" "${type}Profiles" ]) (lib.attrNames types)) listedArgs
  // lib.mapAttrs' (type: lib.nameValuePair "${type}ConfigurationsArgs") configurationsArgs
  // lib.mapAttrs' (type: lib.nameValuePair "${type}Configurations") configurations
