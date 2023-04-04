{
  description = "NixOS configuration library";

  inputs = {
    nixpkgs.url = "github:nix-community/nixpkgs.lib/44214417fe4595438b31bdb9469be92536a61455";
  };

  outputs = {
    self,
    nixpkgs,
  }: {
    lib = import ./lib {
      inherit nixpkgs;
      nixcfg = self;
    };
    tests = let
      results = import ./test/lib {
        inherit nixpkgs;
        nixcfg = self;
      };
    in
      if results == [ ]
      then null
      else results;
  };
}
