{
  name,
  system,
  modules,
  stateVersion,
  pkgs,
  ...
}: let
  inherit (builtins) attrValues catAttrs concatMap concatStringsSep hashString substring;
  inherit (pkgs.input.lib) mapAttrs' mkDefault mkIf versionAtLeast;
in
  concatMap attrValues (catAttrs "nixosModules" nixcfgs)
  ++ modules
  ++ [
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
    })
  ]
