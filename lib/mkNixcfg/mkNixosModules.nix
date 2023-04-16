{
  nixpkgs,
  self,
  nixcfgs,
  nixcfgsChannels,
  nixcfgsModules,
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
    optional
    ;
in
  nixcfgsModules
  ++ modules
  ++ singleton
  ({ config, ... }: {
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
