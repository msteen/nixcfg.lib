{
  description = "NixOS configuration library";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/e2c97799da5f5cd87adfa5017fba971771e123ef";
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
  };
}
