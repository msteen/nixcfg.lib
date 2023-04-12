{
  description = "NixOS configuration library";

  inputs = {
    # nixpkgs.url = "github:nix-community/nixpkgs.lib/44214417fe4595438b31bdb9469be92536a61455";
    nixpkgs.url = "github:NixOS/nixpkgs/e2c97799da5f5cd87adfa5017fba971771e123ef";

    nixos-unstable.url = "github:NixOS/nixpkgs/19cf008bb18e47b6e3b4e16e32a9a4bdd4b45f7e";

    extra-container.url = "github:erikarvstedt/extra-container";
    extra-container.inputs.nixpkgs.follows = "nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
    ...
  } @ inputs: let
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

    testNixcfg = let
      self = nixcfg.lib.mkNixcfg {
        name = "test";
        path = ./test/lib/nixcfg;
        inputs =
          inputs
          // {
            inherit self;
          };
      };
    in
      self;
  };
}
