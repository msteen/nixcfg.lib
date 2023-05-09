{
  description = "NixOS configuration library";

  inputs = {
    # We use the latest stable release because it also acts as the fallback nixpkgs.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-22.11";

    flake-utils.url = "github:numtide/flake-utils";

    alejandra.url = "github:msteen/alejandra";
    alejandra.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    ...
  }: let
    nixcfg = self;

    # Do not allow overwriting expected behaviours of builtins and standard lib.
    # We cannot reuse the lib output, as a lot of lib code is already needed to determine it.
    lib = nixcfg.lib // nixpkgs.lib // builtins;
  in {
    lib = import ./lib {
      inherit lib nixcfg nixpkgs;
    };

    # packages = lib.genAttrs [ "x86_64-linux" ] (system: let
    #   pkgs = nixpkgs.legacyPackages.${system};
    # in {
    #   doc = (import ./lib/mkNixcfg/docs { inherit lib nixcfg pkgs; }).html;
    # });

    # checks = lib.genAttrs [ "x86_64-linux" ] (system: let
    #   pkgs = nixpkgs.legacyPackages.${system};
    #   alejandra = inputs.alejandra.defaultPackage.${system};
    # in {
    #   # tests = pkgs.writeShellApplication {
    #   #   name = "tests";
    #   #   runtimeInputs = [ alejandra ];
    #   #   text = ''
    #   #     out=$(nix eval ${toString ./test/lib}#tests)
    #   #     if [[ $out == null ]]; then
    #   #       echo "all tests passed"
    #   #     else
    #   #       echo "some tests failed:"
    #   #       alejandra -q <<< "$out"
    #   #       exit 1
    #   #     fi
    #   #   '';
    #   # };
    #   # tests = pkgs.runCommand "tests" { buildInputs = [ pkgs.nix alejandra ]; } ''
    #   #   out=$(nix --extra-experimental-features nix-command eval ${toString ./test/lib}#tests)
    #   #   if [[ $out == null ]]; then
    #   #     echo "all tests passed"
    #   #   else
    #   #     echo "some tests failed:"
    #   #     alejandra <<< "$out"
    #   #     exit 1
    #   #   fi
    #   # '';
    # });
  };
}
