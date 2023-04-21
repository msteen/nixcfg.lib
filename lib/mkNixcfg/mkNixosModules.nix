{
  nixpkgs,
  self,
  nixcfgs,
  nixcfgsInputs,
  mkDefaultModules,
  requireSops,
  homeApplyArgs,
  mkSpecialArgs,
  mkHomeModules,
}: {
  name,
  inputs,
  system,
  stateVersion,
  modules,
  channels,
  pkgs,
  ...
}: let
  inherit
    (builtins)
    catAttrs
    concatStringsSep
    hashString
    mapAttrs
    substring
    ;
  inherit
    (nixpkgs.lib)
    mapAttrs'
    singleton
    versionAtLeast
    ;
  inherit
    (pkgs.lib)
    mkDefault
    mkIf
    mkOverride
    optional
    optionals
    ;
in
  mkDefaultModules "nixos"
  ++ modules
  ++ optionals requireSops [
    (inputs.sops-nix or nixcfgsInputs.sops-nix).nixosModules.sops
    ./profiles/sops.nix
  ]
  ++ optionals (homeApplyArgs ? ${name}) (let
    homeArgs = homeApplyArgs.${name};
  in [
    (homeArgs.inputs.home-manager or nixcfgsInputs.home-manager).nixosModules.home-manager
    {
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        extraSpecialArgs = mkSpecialArgs homeArgs;
        users = mapAttrs (username: user: { imports = mkHomeModules homeArgs username user; }) homeArgs.users;
      };

      # Prevent conflicting definition values due to:
      # https://github.com/nix-community/home-manager/blob/40ebb62101c83de81e5fd7c3cfe5cea2ed21b1ad/nixos/common.nix#L34
      users.users =
        mapAttrs (username: { homeDirectory, ... }: {
          isNormalUser = true;
          # Make the override 1 stronger than `mkDefault`,
          # thus overriding `mkDefault "users"` while still make it easy to override.
          # The use of a users main group is outdated due to security concerns, such as giving accidental write access.
          group = mkOverride 999 username;
          home = homeDirectory;
        })
        homeArgs.users;
      users.groups = mapAttrs (_: _: { }) homeArgs.users;
    }
  ])
  ++ singleton ({ config, ... }: {
    nix.extraOptions = "extra-experimental-features = ${concatStringsSep " "
      ([ "nix-command" "flakes" ] ++ optional (!versionAtLeast config.nix.package.version "2.5pre") "ca-references")}";

    environment.etc =
      mapAttrs' (name: input: {
        name = "nix/inputs/${name}";
        value.source = input.outPath;
      })
      inputs;
    nix.nixPath = [ "/etc/nix/inputs" ];
    nix.registry = mapAttrs (_: input: { flake = input; }) inputs;

    networking.hostName = mkDefault name;
    networking.hostId = mkDefault (substring 0 8 (hashString "sha256" name));

    nixpkgs.pkgs = mkDefault pkgs;
    nixpkgs.overlays = [ (final: prev: channels) ] ++ catAttrs "overlay" nixcfgs;

    system.nixos.revision = mkDefault config.system.configurationRevision;
    system.nixos.versionSuffix = mkDefault ".${substring 0 8 (self.lastModifiedDate or "19700101")}.${self.shortRev or "dirty"}";
    system.stateVersion = stateVersion;
    system.configurationRevision = mkIf (self ? rev) self.rev;
  })
