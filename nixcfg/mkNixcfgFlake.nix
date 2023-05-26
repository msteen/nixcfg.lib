{
  lib,
  inputs,
}: config: let
  constants = import ./constants.nix;

  nixcfg = lib.mkNixcfg [
    {
      path = config.inputs.self.outPath;
      sources = lib.inputsToSources config.inputs;

      # It is not possible to just convert flake inputs to sources and have them be handled like any other nixcfg,
      # because the possibility that flake inputs might get overridden needs to be taken into account.
      # Due to the config allowing nixcfgs to be listed directly, flake-based nixcfgs can be handled
      # by beforehand already flattening all flake-based nixcfgs based on their inputs.
      # The end result will be that the list of nixcfgs will be completely flake free,
      # yet flakes will have be taken into account and the nixcfg implementation will remain free
      # of anything flake specific.
      nixcfgs = let
        recurFlake = flake: recur flake.inputs flake.nixcfg.config.nixcfgs ++ [ flake.nixcfg ];
        recur = inputs: nixcfgs: (lib.concatMap (x: let
          name = constants.nixcfgPrefix + x;
        in
          if x ? nixcfg
          then recurFlake x
          else if lib.isString x && inputs ? ${name}
          then recurFlake inputs.${name}
          else [ x ])
        nixcfgs);
      in
        # There is no need for specialized deduplication logic. What is already in place for nixcfgs works here as well,
        # because when deduplicating only the first value of values that share a name is ever considered,
        # which given how things are ordered, will always be the nixcfgs based on the flake inputs.
        recur config.inputs config.nixcfgs or [ ];

      apply.channels = _: { overlays = [ inputs.alejandra.overlay ]; };

      apply.nixosConfigurations = _: {
        modules = lib.singleton (let
          inherit (config) inputs;
          inherit (inputs) self;
        in
          {
            config,
            pkgs,
            ...
          }: {
            environment.systemPackages = [ pkgs.alejandra ];

            nix.registry = lib.mapAttrs (_: input: { flake = input; }) inputs;

            # The attributes `rev` and `shortRev` are only available when the input is marked to be a git input.
            # Even something with type path contains a git repo, it will be ignored.
            system.configurationRevision = lib.mkIf (self ? rev) self.rev;
            system.nixos.revision = lib.mkDefault config.system.configurationRevision;
            system.nixos.versionSuffix = lib.mkDefault ".${lib.substring 0 8 (self.lastModifiedDate or "19700101")}.${self.shortRev or "dirty"}";
          });
      };

      apply.homeConfigurations = _: {
        users = _: {
          modules = [ ({ pkgs, ... }: { home.packages = [ pkgs.alejandra ]; }) ];
        };
      };
    }
    (removeAttrs config [ "inputs" "nixcfgs" ])
  ];

  self = let
    inherit (nixcfg) config nixcfgs;
  in
    {
      inherit nixcfg;

      packages = let
        list = lib.concatMapAttrsToList (type:
          lib.mapAttrsToList (name: value: let
            configuration = nixcfg.configurations.${type}.${name};
            system =
              configuration.system
              or configuration.pkgs.system
              or (throw "The ${type} configuration is missing a system or pkgs attribute.");
          in {
            inherit system value;
            name = "${type}_${name}";
          }))
        nixcfgs.packages;
      in
        lib.mapAttrs (_: lib.listToAttrs) (lib.groupBy (x: x.system) list);

      inherit (nixcfgs) overlays;

      formatter =
        lib.genAttrs config.systems (system:
          self.legacyPackages.${system}.alejandra);

      legacyPackages = lib.mapAttrs (_: x: x.nixpkgs) nixcfgs.channels;
    }
    // lib.mapAttrs' (type: lib.nameValuePair "${type}Configurations") nixcfgs.configurations
    // lib.mapToAttrs (type: lib.nameValuePair "${type}Modules" nixcfgs.modules.${type}) constants.configurationTypes;
in
  self
