{
  description = "Nix configuration";

  inputs = {
    nixpkgs.follows = "nixos-22_11";
    nixos-22_11.url = "github:NixOS/nixpkgs/fd901ef4bf93499374c5af385b2943f5801c0833";
    nixos-unstable.url = "github:NixOS/nixpkgs/19cf008bb18e47b6e3b4e16e32a9a4bdd4b45f7e";

    extra-container = {
      url = "github:erikarvstedt/extra-container";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-22.11";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.utils.follows = "extra-container/flake-utils";
    };
  };

  outputs = _: { };
}
