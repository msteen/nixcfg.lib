{
  description = "Nix configuration";

  inputs = {
    nixos-22_11.url = "github:NixOS/nixpkgs/nixos-22.11";
    # This is pinned to a commit of the day before nixcfg.lib its nixos 23.11,
    # such that we can differentiate them and properly test whether the fallbacks work as intended.
    nixos-23_11.url = "github:NixOS/nixpkgs/fb0c047e30b69696acc42e669d02452ca1b55755";
    nixos-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-stable.follows = "nixos-23_11";
    nixpkgs.follows = "nixos-stable";

    extra-container = {
      url = "github:erikarvstedt/extra-container";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-23.11";
      inputs.nixpkgs.follows = "nixos-23_11";
    };
  };

  outputs = _: { };
}
