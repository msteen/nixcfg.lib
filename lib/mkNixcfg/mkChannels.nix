{ lib }: let
  importChannel = nixcfgsOverlays: {
    input,
    system,
    config ? { },
    overlays ? [ ],
    ...
  }:
    importNixpkgs {
      inherit input system;
      config = { allowUnfree = true; } // config;
      overlays =
        (
          if lib.isFunction overlays
          then overlays nixcfgsOverlays
          else overlays
        )
        ++ [ (final: prev: { inherit input; }) ];
    };

  importNixpkgs = {
    input,
    system,
    config ? { },
    overlays ? [ ],
    ...
  }:
  # Skip impure.nix: ${input} -> ${input}/pkgs/top-level/impure.nix -> ${input}/pkgs/top-level
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
          name = "nixpkgs-${name}-patched${lib.optionalString (input ? shortRev) ".git.${input.shortRev}"}";
          src = input;
          inherit patches;
        };
      };
in
  {
    nixcfgsOverlays,
    channels,
  }: inputs: systems:
    lib.genAttrs systems (system:
      lib.mapAttrs (name: channel:
        importChannel nixcfgsOverlays (patchChannel name channel)) (
        lib.mapAttrs (_: input: { inherit input system; }) inputs
        // lib.mapAttrs (
          name: channel: let
            input =
              if channel.input or null == null
              then
                inputs.${name}
                or (throw "Channel '${name}' is missing the required input attribute or does not have it implicit through inputs.")
              else channel.input;
          in
            channel // { inherit input system; }
        )
        channels
      ))
