{
  description = "NixOS configuration library";

  inputs = {
    # We use the latest stable release because it also acts as the fallback nixpkgs.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-22.11";

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    alejandra.url = "github:msteen/alejandra";
    alejandra.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    alejandra,
    ...
  }: let
    sources = lib.inputsToSources { inherit nixpkgs; };

    baseNixcfgLib = import ./lib { nixpkgs = nixpkgs.outPath; };
    nixcfgLib = baseNixcfgLib.extend (_: _:
      import ./nixcfg {
        inherit lib nixcfg sources;
        alejandraOverlay = alejandra.overlay;
      });
    # FIXME: Note on how it needs to be in this order for evalModules to pass it along correctly.
    lib = (nixcfgLib.mkNixpkgsLib nixpkgs.outPath).extend (_: _: nixcfgLib);

    nixcfg = {
      lib = nixcfgLib;
      inherit (self) outPath;
    };
  in {
    inherit lib;

    packages = lib.genAttrs [ "x86_64-linux" ] (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      htmlDocs = import ./docs { inherit lib nixcfg pkgs; };
    });

    tests =
      import ./test/lib {
        inherit lib;
      }
      ++ import ./test/nixcfg {
        inherit lib nixcfg;
        inherit (sources) nixpkgs;
      };
  };
}
