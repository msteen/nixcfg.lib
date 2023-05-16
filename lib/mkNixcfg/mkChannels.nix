{
  lib,
  defaultOverlays,
}: let
  importChannel = nixcfgsOverlays: {
    source,
    system,
    config ? { },
    overlays ? [ ],
    ...
  }:
    importNixpkgs {
      inherit source system;
      config = { allowUnfree = true; } // config;
      overlays =
        defaultOverlays
        ++ (
          if lib.isFunction overlays
          then overlays nixcfgsOverlays
          else overlays
        );
    };

  importNixpkgs = {
    source,
    system,
    config ? { },
    overlays ? [ ],
    ...
  }:
  # Skip impure.nix: ${source} -> ${source}/pkgs/top-level/impure.nix -> ${source}/pkgs/top-level
    import (source + "/pkgs/top-level") {
      localSystem = { inherit system; };
      inherit config overlays;
    };

  patchChannel = name: channel @ {
    source,
    system,
    patches ? [ ],
    ...
  }:
    if patches == [ ]
    then channel
    else
      channel
      // {
        source = (importNixpkgs { inherit source system; }).applyPatches {
          name = "nixpkgs-${name}-patched";
          src = source;
          inherit patches;
        };
      };
in
  {
    nixcfgsOverlays,
    channels,
  }: sources: systems:
    lib.genAttrs systems (system:
      lib.mapAttrs (name: channel:
        importChannel nixcfgsOverlays (patchChannel name channel)) (
        lib.mapAttrs (_: source: { inherit source system; }) sources
        // lib.mapAttrs (
          name: channel: let
            source =
              if channel.source or null == null
              then
                sources.${name}
                or (throw "Channel '${name}' is missing the required source attribute or does not have it implicit through sources.")
              else channel.source;
          in
            channel // { inherit source system; }
        )
        channels
      ))
