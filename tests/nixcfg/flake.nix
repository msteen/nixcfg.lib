{
  description = "Nix configuration";

  inputs = {
    nixpkgs.follows = "nixos-23_11";
    nixos-23_11.url = "github:NixOS/nixpkgs/fb0c047e30b69696acc42e669d02452ca1b55755";
    nixos-unstable.url = "github:NixOS/nixpkgs/fb0c047e30b69696acc42e669d02452ca1b55755";

    extra-container = {
      url = "github:erikarvstedt/extra-container";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-23.11";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.utils.follows = "extra-container/flake-utils";
    };
  };

  outputs = _: { };
}
