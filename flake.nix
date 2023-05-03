{
  description = "NixOS configuration library";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-22.11";

    alejandra.url = "github:msteen/alejandra";
    alejandra.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    ...
  } @ inputs: let
    nixcfg = self;

    # Do not allow overwriting expected behaviours of builtins and standard lib.
    # We cannot reuse the lib output, as a lot of lib code is already needed to determine it.
    lib = nixcfg.lib // nixpkgs.lib // builtins;
  in {
    lib = import ./lib { inherit lib nixcfg nixpkgs; };

    tests = let
      results = import ./test/lib { inherit lib nixpkgs; };
    in
      if results == [ ]
      then null
      else results;
  };
}
