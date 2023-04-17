{
  nixpkgs,
  self,
  nixcfgs,
  nixcfgsInputs,
  nixcfgsChannels,
  homeApplyArgs,
  mkSpecialArgs,
  mkHomeModules,
}: {
  name,
  inputs,
  system,
  pkgs,
  stateVersion,
  modules,
  ...
}: let
  inherit
    (builtins)
    attrValues
    catAttrs
    concatMap
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
    optional
    optionals
    ;
in
  concatMap attrValues (catAttrs "nixosModules" nixcfgs)
  ++ modules
  ++ optionals (homeApplyArgs ? ${name}) (let
    homeArgs = homeApplyArgs.${name};
  in [
    (homeArgs.inputs.home-manager or nixcfgsInputs.home-manager).nixosModules.home-manager
    {
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        extraSpecialArgs = mkSpecialArgs homeArgs;
        users = mapAttrs (mkHomeModules homeArgs) homeArgs.users;
      };
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
    nixpkgs.overlays = [ (final: prev: nixcfgsChannels) ] ++ catAttrs "overlay" nixcfgs;

    system.configurationRevision = mkIf (self ? rev) self.rev;
    system.stateVersion = stateVersion;

    system.nixos.revision = mkDefault config.system.configurationRevision;
    system.nixos.versionSuffix = mkDefault pkgs.lib.trivial.versionSuffix;
  })
