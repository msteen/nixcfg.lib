{
  description = "Nix configuration";

  inputs = {
    nixpkgs.follows = "nixos-22_11";
    nixos-22_11.url = "github:NixOS/nixpkgs/fd901ef4bf93499374c5af385b2943f5801c0833";
    nixos-unstable.url = "github:NixOS/nixpkgs/19cf008bb18e47b6e3b4e16e32a9a4bdd4b45f7e";

    nixcfg.url = "path:../..";
    nixcfg.inputs.nixpkgs.follows = "nixpkgs";

    extra-container.url = "github:erikarvstedt/extra-container";
    extra-container.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-22.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.inputs.utils.follows = "extra-container/flake-utils";

    flake-compat.url = "github:edolstra/flake-compat";
    flake-compat.flake = false;
  };

  outputs = _: { };
}
