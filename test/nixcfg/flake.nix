{
  description = "Nix configuration";

  inputs = {
    nixos-22_11.url = "github:NixOS/nixpkgs/nixos-22.11";
    nixos-23_05.url = "github:NixOS/nixpkgs/nixos-23.05";
    nixos-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-stable.follows = "nixos-23_05";
    nixpkgs.follows = "nixos-stable";

    extra-container = {
      url = "github:erikarvstedt/extra-container";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-23.05";
      inputs.nixpkgs.follows = "nixos-23_05";
    };
  };

  outputs = _: { };
}
