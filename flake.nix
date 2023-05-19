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
    # Do not allow overwriting expected behaviours of builtins and standard lib.
    # We cannot reuse the lib output, as a lot of lib code is already needed to determine it.
    lib = nixcfg.lib // nixpkgs.lib // builtins;

    sources = lib.inputsToSources { inherit nixpkgs; };

    nixcfg = {
      lib =
        (import ./lib {
          nixpkgs = nixpkgs.outPath;
        })
        .extend (final: prev:
          import ./nixcfg {
            inherit nixcfg sources;
            lib = (prev.mkNixpkgsLib nixpkgs.outPath).extend (_: _: prev);
            alejandraOverlay = alejandra.overlay;
          });

      inherit (self) outPath;
    };
  in {
    inherit (nixcfg) lib;

    packages = lib.genAttrs [ "x86_64-linux" ] (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      htmlDocs = import ./docs { inherit lib nixcfg pkgs; };
    });

    tests = let
      results = import ./test/lib {
        inherit lib nixcfg;
        inherit (sources) nixpkgs;
      };
    in
      if results == [ ]
      then null
      else results;
  };
}
