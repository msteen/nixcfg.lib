{
  lib,
  nixcfg,
  sources,
}: let
  constants = import ./constants.nix;

  inherit (sources) nixpkgs;

  requiredSources = {
    nixos = [ ];
    container = [ "extra-container" ];
    home = [ "home-manager" ];
  };

  configurationToPackage = {
    nixos = configuration: configuration.config.system.build.toplevel;
    container = configuration: let
      inherit (configuration.config.nixpkgs) pkgs;
    in
      configuration.config.system.build.etc.overrideAttrs (old: {
        name = "container";
        buildCommand =
          old.buildCommand
          + "\n"
          + ''
            mkdir -p $out/bin
            cat <<EOF > $out/bin/container
              #!${pkgs.runtimeShell}
              EXTRA_CONTAINER_ETC=$out exec extra-container "\$@"
            EOF
            chmod +x $out/bin/container
          '';
      });
    home = configuration: configuration.activationPackage;
  };

  mkConfig = import ./mkConfig.nix { inherit lib; };
  mkNixcfgs = import ./mkNixcfgs.nix { inherit lib; };
  mkChannels = import ./mkChannels.nix { inherit lib; };

  # This filters out the sources for nixpkgs and all official nixpkgs channel branches.
  filterNixpkgsSources = lib.filterAttrs (
    name: _:
      lib.elem name [ "nixpkgs" "nixpkgs-unstable" ]
      || lib.hasPrefix "nixos-" name
      || lib.hasPrefix "release-" name
  );

  # This will make sure there always is a nixpkgs channel to fallback on.
  # The order of fallback preference is as follows:
  # - sources.nixos-00_00
  # - sources.nixos-unstable
  # - sources.nixpkgs-00_00
  # - sources.nixpkgs-unstable
  # - nixcfg.sources.nixpkgs
  sourcesWithDefaultNixpkgs = sources: let
    # The builtin `compareVersions` orders digits before letters,
    # so no special case to handle unstable is needed.
    latestSources =
      lib.mapAttrs (_name: names: sources.${lib.maximum lib.compareVersions names})
      (lib.groupBy (name: lib.head (lib.splitVersion name)) (lib.attrNames sources));
  in
    sources
    // lib.optionalAttrs (!sources ? nixpkgs) {
      nixpkgs = latestSources.nixos or latestSources.release or nixpkgs;
    };

  mkNixcfg = self: x: let
    config = mkConfig (lib.toList x);

    inherit (mkNixcfgs config.sources config.nixcfgs self) nixcfgs nixcfgsAttrs;

    nixcfgsSources = lib.concatAttrs (lib.mapGetAttrPath [ "config" "sources" ] nixcfgs);
    nixcfgsNixpkgsSources = sourcesWithDefaultNixpkgs (filterNixpkgsSources nixcfgsSources);

    libNixpkgs = let
      inherit (config.lib) channelName;
    in
      nixcfgsNixpkgsSources.${channelName}
      or (throw "The lib nixpkgs channel '${channelName}' does not exist.");

    # The nixpkgs lib has to be passed as an overlay too for it to be available for use
    # in the configured lib overlays (via `prev.lib`).
    libOverlays = lib.singleton (_: { lib = nixpkgsLib; }) ++ config.lib.overlays;

    nixpkgsLib = lib.mkNixpkgsLib libNixpkgs;
    nixcfgsLib = lib.extendsList (map (libOverlay: (final: prev:
      libOverlay {
        self = final;
        inherit (prev) lib;
      })) (lib.concatLists (lib.catAttrs "libOverlays" nixcfgs))) (final: nixcfg.lib);
    outputLib = lib.extendNew nixpkgsLib nixcfgsLib;

    mkChannels' = mkChannels {
      # The channel overlays option allows you to pass a function
      # expecting the attrset containing all available overlays.
      nixcfgsOverlays = lib.mapAttrs (_: lib.getAttrPath [ "config" "overlays" ]) nixcfgsAttrs;
      inherit (config) channels;
    };

    nixcfgsChannels = mkChannels' nixcfgsNixpkgsSources config.systems;

    configurationsArgs = lib.genAttrs constants.configurationTypes (
      type:
        lib.mapAttrs (name: {
            system,
            channelName,
            ...
          } @ configuration: let
            sources = sourcesWithDefaultNixpkgs (
              nixcfgsSources
              // configuration.sources
            );

            # The configuration sources could contain additional channels.
            # To maximize sharing, the new channels are merged with the nixcfgs channels.
            channels =
              (mkChannels' (filterNixpkgsSources sources) [ system ]).${system}
              // nixcfgsChannels.${system};

            pkgs =
              channels.${channelName}
              or (throw "The ${type} nixpkgs channel '${channelName}' does not exist.");

            unavailableSources =
              lib.filter (requiredSource: !sources ? ${requiredSource})
              (requiredSources.${type} ++ lib.optional config.requireSops "sops-nix");
          in
            if unavailableSources != [ ]
            then throw "The ${type} configuration '${name}' did not specify '${lib.head unavailableSources}' as part of their sources."
            else
              configuration
              // {
                inherit channels name pkgs sources;
              })
        config."${type}Configurations"
    );

    mkSpecialArgs = type: {
      name,
      sources,
      moduleArgs,
      ...
    }:
      {
        # We cannot inherit name, as it will conflict with the workings of submodules.
        # It would for example lead to misconfiguring home manager.
        inherit sources;

        # By default the lib containing `evalModules` is used,
        # but we do not always have control over which lib is used for this,
        # so we pass it explicitly as a special argument, which overwrites the default.
        lib = outputLib;

        # In case only nixcfg's extensions to lib are needed.
        nixcfg.lib = nixcfgsLib;

        data = lib.mapAttrs (_: lib.getAttrPath [ "config" "data" ]) nixcfgsAttrs;
        profiles = lib.mapAttrs (_: lib.getAttrPath [ "config" "${type}Profiles" ]) nixcfgsAttrs;
      }
      // moduleArgs;

    mkDefaultModules = type: name:
      lib.concatMap lib.attrValues (lib.mapGetAttrPath [ "config" "${type}Modules" ] nixcfgs)
      ++ lib.catAttrs "base" (lib.mapGetAttrPath [ "config" "${type}Profiles" ] nixcfgs)
      ++ lib.optional (config.requireSops && lib.elem type [ "nixos" "home" ]) {
        sops.defaultSopsFile = config.path + "/${type}/configs/${name}/secrets.yaml";
      };

    defaultOverlays = lib.catAttrs "default" (lib.mapGetAttrPath [ "config" "overlays" ] nixcfgs);

    mkNixosModules = import ./mkNixosModules.nix {
      inherit config defaultOverlays lib mkDefaultModules mkHomeModules mkSpecialArgs;
      homeConfigurationsArgs = configurationsArgs.home;
    };

    mkHomeModules = import ./mkHomeModules.nix {
      inherit config defaultOverlays lib mkDefaultModules;
    };

    # One set of configuration arguments could lead to multiple actual such configurations.
    # This is the case for home configurations due to them being build per user.
    mkConfigurations = configurationsArgs: f:
      lib.listToAttrs (lib.concatMapAttrsToList (name: configurationArgs: let
        value = f configurationArgs;
      in
        if !(lib.isList value)
        then lib.singleton (lib.nameValuePair name value)
        else value)
      configurationsArgs);

    configurations = {
      nixos =
        # Only non-overlapping nixos containers are build standalone.
        # See the nixosContainers option description for more details.
        mkConfigurations (removeAttrs configurationsArgs.nixos (lib.attrNames configurationsArgs.container))
        # This is the core of what `nixpkgs.lib.nixosSystem` does.
        # The rest is handled in `mkNixosModules`.
        (args: (import (args.pkgs.path + "/nixos/lib/eval-config.nix") {
          inherit (args) system;
          lib = outputLib;
          specialArgs = mkSpecialArgs "nixos" args;
          modules = mkNixosModules args;
        }));

      container =
        mkConfigurations configurationsArgs.container
        ({
            name,
            sources,
            channelName,
            system,
            stateVersion,
            modules,
            pkgs,
            ...
          } @ args: let
            inherit (lib) types;
            needNewerNixpkgs = lib.compareVersions lib.trivial.release "23.05" < 0;
            newerNixpkgs =
              sources.nixos-23_05
              or sources.nixos-unstable
              or (throw ("To have similar module arguments within containers as in nixos we need special argument support."
                  + " This support has only be added in nixpkgs 23.05, so the nixpkgs channel 'nixos-23_05' or 'nixos-unstable' is required."));
          in
            # Trigger the potential error already when evaluating the config. Do not postpone it until building.
            lib.seq (
              if needNewerNixpkgs
              then newerNixpkgs
              else null
            ) (import (sources.extra-container + "/eval-config.nix") {
              inherit system;

              # Whether to use state version 21.11 (false) or 20.05 (true).
              # It is a required attribute, but meaningless, because it will be overwritten.
              legacyInstallDirs = false;

              # Used to build the containers.
              nixosPath = sources.${channelName} + "/nixos";

              # Counterintuitively the config attribute here is a module.
              systemConfig.imports =
                lib.optional needNewerNixpkgs {
                  disabledModules = [ "virtualisation/nixos-containers.nix" ];
                  imports = [ (newerNixpkgs + "/nixos/modules/virtualisation/nixos-containers.nix") ];
                }
                ++ lib.singleton {
                  # The container configurations live within this submodule.
                  # To make it possible to pass the custom special arguments to the submodule,
                  # the option has to be extended, which can be done by overwriting it, causing a merge.
                  options.containers = lib.mkOption {
                    type = types.attrsOf (types.submoduleWith {
                      shorthandOnlyDefinesConfig = true;
                      modules =
                        mkDefaultModules "container" name
                        ++ modules;
                      specialArgs = mkSpecialArgs "container" args;
                    });
                  };

                  config = {
                    # Set the state version relevant for building the containers.
                    # This overwrites the default based on `legacyInstallDirs`.
                    system = { inherit stateVersion; };

                    nixpkgs = { inherit pkgs; };

                    # Multiple containers can be defined at once, but the commands of the CLI work on all containers defined.
                    # For example, there is no creating a specific container, it will create all of them at once.
                    # The workaround is to only define one container at a time.
                    containers.${name} = let
                      args = configurationsArgs.nixos.${name};
                    in {
                      specialArgs = mkSpecialArgs "nixos" args;
                      config.imports =
                        mkNixosModules args
                        # By default these paths do not exist within the container,
                        # but home manager expects them to exist, so we recreate them.
                        ++ lib.optional (configurationsArgs.home ? ${name}) {
                          systemd.services.fix-home-manager = {
                            serviceConfig = {
                              Type = "oneshot";
                            };
                            script = lib.concatStrings (lib.mapAttrsToList (name: _: ''
                                mkdir -p /nix/var/nix/{profiles,gcroots}/per-user/${name}
                                chown ${name}:root /nix/var/nix/{profiles,gcroots}/per-user/${name}
                              '')
                              configurationsArgs.home.${name}.users);
                            wantedBy = [ "multi-user.target" ];
                          };
                        };
                    };
                  };
                };
            }));

      home =
        mkConfigurations configurationsArgs.home
        ({
            name,
            sources,
            pkgs,
            stateVersion,
            users,
            ...
          } @ args:
            lib.mapAttrsToList (username: user:
              lib.nameValuePair "${name}_${username}" (import (sources.home-manager + "/modules") (let
                specialArgs = mkSpecialArgs "home" args;
              in {
                # Whether to check that each option has a matching declaration.
                check = true;

                # Workaround for Home Manager to prevent its extended lib from being overwritten.
                # Related PR: https://github.com/nix-community/home-manager/pull/3969
                extraSpecialArgs = removeAttrs specialArgs [ "lib" ];
                inherit (specialArgs) lib;

                inherit pkgs;
                configuration = {
                  _file = ./.;
                  imports =
                    mkHomeModules args username user
                    ++ [ { programs.home-manager.path = sources.home-manager; } ];
                  config.nixpkgs = { inherit (pkgs) config overlays; };
                };
              })))
            users);
    };

    packages = lib.mapAttrs (type: lib.mapAttrs (_: configurationToPackage.${type})) configurations;
  in {
    inherit configurations libOverlays nixcfgs packages;
    channels = nixcfgsChannels;

    config = config // { inherit nixcfgs; };

    # To make nixcfg's extensions to lib also available outside configurations.
    lib = outputLib;

    # Makes it possible to convert this attrset to a string.
    outPath = config.path;
  };
in
  x: let self = mkNixcfg self x; in self
