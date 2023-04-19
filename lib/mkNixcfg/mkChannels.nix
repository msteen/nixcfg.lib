{
  nixpkgs,
  nixcfgsOverlays,
  channels,
}: let
  inherit
    (builtins)
    isFunction
    mapAttrs
    ;
  inherit
    (nixpkgs.lib)
    genAttrs
    optionalString
    ;

  importChannel = {
    input,
    system,
    config ? { },
    overlays ? [ ],
  }:
    importNixpkgs {
      inherit input system;
      config = { allowUnfree = true; } // config;
      overlays =
        (
          if isFunction overlays
          then overlays nixcfgsOverlays
          else overlays
        )
        ++ [ (final: prev: { inherit input; }) ];
    };

  # Skip impure.nix: ${input} -> ${input}/pkgs/top-level/impure.nix -> ${input}/pkgs/top-level
  importNixpkgs = {
    input,
    system,
    config ? { },
    overlays ? [ ],
  }:
    import (input + "/pkgs/top-level") {
      localSystem = { inherit system; };
      inherit config overlays;
    };

  patchChannel = name: channel @ {
    input,
    system,
    patches ? [ ],
    ...
  }:
    if patches == [ ]
    then channel
    else
      channel
      // {
        input = (importNixpkgs { inherit input system; }).applyPatches {
          name = "nixpkgs-${name}-patched${optionalString (input ? shortRev) ".git.${input.shortRev}"}";
          src = input;
          inherit patches;
        };
      };
in
  inputs: systems:
    genAttrs systems (system:
      mapAttrs (name: channel:
        importChannel (patchChannel name channel)) (
        mapAttrs (_: input: { inherit input system; }) inputs
        // mapAttrs (
          name: {
            input ?
              inputs.${name}
              or (throw "Channel '${name}' is missing the required input attribute or does not have it implicit through inputs."),
            ...
          } @ channel:
            channel // { inherit input system; }
        )
        channels
      ))
