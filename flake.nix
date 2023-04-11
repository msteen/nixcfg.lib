{
  description = "NixOS configuration library";

  inputs = {
    nixpkgs.url = "github:nix-community/nixpkgs.lib/44214417fe4595438b31bdb9469be92536a61455";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    nixcfg = self;
  in {
    lib = import ./lib {
      inherit nixcfg nixpkgs;
    };

    tests = let
      results = import ./test/lib {
        inherit nixcfg nixpkgs;
      };
    in
      if results == [ ]
      then null
      else results;
  };
}
