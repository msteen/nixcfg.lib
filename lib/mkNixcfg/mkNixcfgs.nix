{ nixpkgs }: let
  inherit
    (builtins)
    attrValues
    catAttrs
    concatLists
    ;
  inherit
    (nixpkgs.lib)
    filterAttrs
    hasPrefix
    unique
    ;
in
  inputs: let
    inherit (inputs) self;
    nixcfgInputs = attrValues (filterAttrs (name: _: hasPrefix "nixcfg-" name) inputs);
  in
    unique (concatLists (catAttrs "nixcfgs" nixcfgInputs) ++ [ self ])
