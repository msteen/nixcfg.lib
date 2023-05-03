{
  lib,
  self,
  nixcfgs,
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
}:
mkDefaultModules "nixos" name
++ modules
++ lib.optional requireSops inputs.sops-nix.nixosModules.sops
++ lib.optionals (homeApplyArgs ? ${name}) (let
  homeArgs = homeApplyArgs.${name};
in [
  homeArgs.inputs.home-manager.nixosModules.home-manager
  {
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      extraSpecialArgs = mkSpecialArgs "home" homeArgs;
      users = lib.mapAttrs (username: user: { imports = mkHomeModules homeArgs username user; }) homeArgs.users;
    };

    # Prevent conflicting definition values due to:
    # https://github.com/nix-community/home-manager/blob/40ebb62101c83de81e5fd7c3cfe5cea2ed21b1ad/nixos/common.nix#L34
    users.users =
      lib.mapAttrs (username: { homeDirectory, ... }: {
        isNormalUser = true;
        # Make the override 1 stronger than `mkDefault`,
        # thus overriding `mkDefault "users"` while still make it easy to override.
        # The use of a users main group is outdated due to security concerns, such as giving accidental write access.
        group = lib.mkOverride 999 username;
        home = homeDirectory;
      })
      homeArgs.users;
    users.groups = lib.mapAttrs (_: _: { }) homeArgs.users;
  }
])
++ lib.singleton ({ config, ... }: {
  nix.extraOptions = "extra-experimental-features = ${lib.concatStringsSep " "
    ([ "nix-command" "flakes" ] ++ lib.optional (!lib.versionAtLeast config.nix.package.version "2.5pre") "ca-references")}";

  environment.etc =
    lib.mapAttrs' (name: input: {
      name = "nix/inputs/${name}";
      value.source = input.outPath;
    })
    inputs;
  nix.nixPath = [ "/etc/nix/inputs" ];
  nix.registry = lib.mapAttrs (_: input: { flake = input; }) inputs;

  networking.hostName = lib.mkDefault name;
  networking.hostId = lib.mkDefault (lib.substring 0 8 (lib.hashString "sha256" name));

  nixpkgs.pkgs = lib.mkDefault pkgs;
  nixpkgs.overlays = [ (final: prev: channels) ] ++ lib.catAttrs "overlay" nixcfgs;

  system.nixos.revision = lib.mkDefault config.system.configurationRevision;
  system.nixos.versionSuffix = lib.mkDefault ".${lib.substring 0 8 (self.lastModifiedDate or "19700101")}.${self.shortRev or "dirty"}";
  system.stateVersion = stateVersion;
  system.configurationRevision = lib.mkIf (self ? rev) self.rev;
})
