{
  description = "NixOS configuration library";

  inputs = {
    # We use the latest stable release because it also acts as the fallback nixpkgs.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    alejandra.url = "github:msteen/alejandra";
    alejandra.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs: let
    nixcfgLib =
      (import ./lib { nixpkgs = inputs.nixpkgs.outPath; })
      .extend (_: _: import ./nixcfg { inherit inputs lib nixcfg sources; });

    # To prevent unexpected behavior due to accidentally overwriting anything already in nixpkgs,
    # the nixcfg lib extensions should be updated by the original nixpkgs lib instead of the other way around.
    # Unfortunately the only correct way to update the original nixpkgs lib is to add an overlay.
    # Doing it any other way would not update the final lib, which is especially important for e.g. `evalModules`.
    # As it will pass the final lib to its modules as well, lacking the extensions if no overlay was used.
    lib = nixcfgLib.extendNew nixcfgLib.lib nixcfgLib;

    nixcfg = {
      lib = nixcfgLib;
      inherit (inputs.self) outPath;
    };

    sources = lib.inputsToSources inputs;
  in {
    inherit lib;

    packages = lib.genAttrs [ "x86_64-linux" ] (system: let
      pkgs = inputs.nixpkgs.legacyPackages.${system};
    in {
      htmlDocs = import ./docs { inherit lib nixcfg pkgs; };
    });

    tests =
      import ./test/lib {
        inherit lib;
      }
      ++ import ./test/nixcfg {
        inherit lib;
        inherit (sources) nixpkgs;
      };

    tests2 = import ./tests/nixcfg {
      inherit lib;
      inherit (sources) nixpkgs;
    };
  };
}
