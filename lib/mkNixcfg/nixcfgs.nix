{
  nixpkgs,
  inputs,
}: let
  inherit (builtins) attrValues catAttrs concatLists;
  inherit (nixpkgs.lib) filterAttrs hasPrefix unique;
  inherit (inputs) self;
in let
  nixcfgInputs = attrValues (filterAttrs (name: _: hasPrefix "nixcfg-" name) inputs);
in
  unique (concatLists (catAttrs "nixcfgs" nixcfgInputs) ++ [ self ])
