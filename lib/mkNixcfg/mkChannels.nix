{
  nixpkgs,
  channels,
}: systems: inputs: let
  inherit (builtins) mapAttrs;
  inherit (nixpkgs.lib) filterAttrs genAttrs hasPrefix optionalString;

  channelInputs =
    filterAttrs (
      name: _:
        name
        == "nixpkgs"
        || hasPrefix "nixos-" name
        || hasPrefix "release-" name
    )
    inputs;

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

  getChannels = system:
    mapAttrs (_: input: { inherit input system; }) channelInputs
    // mapAttrs (
      name: {
        input ?
          channelInputs.${name}
          or (throw "Channel '${name}' is missing the required input attribute or does not have it implicit through inputs."),
        ...
      } @ channel:
        channel // { inherit input system; }
    )
    channels;

  importChannel = {
    input,
    system,
    config ? { },
    overlays ? [ ],
  }:
    importNixpkgs {
      inherit input overlays system;
      config = { allowUnfree = true; } // config;
    }
    // { inherit input; };
in
  genAttrs systems (system:
    mapAttrs (name: channel:
      importChannel (patchChannel name channel)) (getChannels system))
