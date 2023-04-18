{
  description = "Nix configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/e2c97799da5f5cd87adfa5017fba971771e123ef";
    nixos-unstable.url = "github:NixOS/nixpkgs/19cf008bb18e47b6e3b4e16e32a9a4bdd4b45f7e";

    nixcfg.url = "path:../..";
    nixcfg.inputs.nixpkgs.follows = "nixpkgs";

    extra-container.url = "github:erikarvstedt/extra-container";
    extra-container.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-22.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    flake-compat.url = "github:edolstra/flake-compat";
    flake-compat.flake = false;
  };

  outputs = _: { };
}
