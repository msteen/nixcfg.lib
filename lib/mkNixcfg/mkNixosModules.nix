{
  lib,
  config,
  defaultOverlays,
  homeConfigurationsArgs,
  mkSpecialArgs,
  mkDefaultModules,
  mkHomeModules,
}: {
  name,
  sources,
  system,
  stateVersion,
  modules,
  channels,
  pkgs,
  ...
}:
mkDefaultModules "nixos" name
++ modules
++ lib.optional config.requireSops (sources.sops-nix + "/modules/sops")
++ lib.optionals (homeConfigurationsArgs ? ${name}) (let
  homeConfigurationArgs = homeConfigurationsArgs.${name};
  specialArgs = mkSpecialArgs "home" homeConfigurationArgs;
in [
  (homeConfigurationArgs.sources.home-manager + "/nixos")
  {
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;

      # See the standalone home configuration `extraSpecialArgs` as to why we need remove lib.
      extraSpecialArgs = removeAttrs specialArgs [ "lib" ];

      users =
        lib.mapAttrs (username: user: {
          imports = mkHomeModules homeConfigurationArgs username user;
        })
        homeConfigurationArgs.users;
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
      homeConfigurationArgs.users;
    users.groups = lib.mapAttrs (_: _: { }) homeConfigurationArgs.users;
  }
])
++ lib.singleton ({ config, ... }: {
  nix.extraOptions = "extra-experimental-features = ${lib.concatStringsSep " "
    ([ "nix-command" "flakes" ] ++ lib.optional (!lib.versionAtLeast config.nix.package.version "2.5pre") "ca-references")}";

  environment.etc =
    lib.mapAttrs' (name: source: {
      name = "nix/sources/${name}";
      value = { inherit source; };
    })
    sources;
  nix.nixPath = [ "/etc/nix/sources" ];

  networking.hostName = lib.mkDefault name;
  networking.hostId = lib.mkDefault (lib.substring 0 8 (lib.hashString "sha256" name));

  nixpkgs.pkgs = lib.mkDefault pkgs;
  nixpkgs.overlays = [ (final: prev: channels) ] ++ defaultOverlays;

  environment.systemPackages = [ pkgs.alejandra ];

  system.stateVersion = stateVersion;
})
