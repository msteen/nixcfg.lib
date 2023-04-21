{
  nixpkgs,
  nixcfg,
}: let
  inherit (builtins)
    attrValues
    catAttrs
    concatLists
    ;
  inherit (nixpkgs.lib)
    attrVals
    filterAttrs
    hasPrefix
    nameValuePair
    unique
    ;
  inherit (nixcfg.lib)
    mapToAttrs
    ;
in
  inputs: let
    inherit (inputs) self;
    nixcfgInputs = attrValues (filterAttrs (name: _: hasPrefix "nixcfg-" name) inputs);
    nixcfgs = concatLists (catAttrs "nixcfgs" nixcfgInputs) ++ [ self ];
  in rec {
    attrs = mapToAttrs (nixcfg: nameValuePair nixcfg.name nixcfg) nixcfgs;
    list = attrVals (unique (catAttrs "name" nixcfgs)) attrs;
  }
