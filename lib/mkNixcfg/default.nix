{
  nixpkgs,
  nixcfg,
}: {
  name,
  path,
  inputs,
  ...
} @ rawArgs: let
  nixcfgs = import ./nixcfgs.nix { inherit inputs nixpkgs; };
  # configurationDefaults = mapAttrs (_: defaults:
  #   {
  #     inputs = { };
  #     channelName = "nixpkgs";
  #     system = "x86_64-linux";
  #     moduleArgs = { };
  #     stateVersion = "22.11";
  #   }
  #   // defaults) {
  #   nixos = { modules = [ ]; };
  #   container = { modules = [ ]; };
  #   home = {
  #     users = _: {
  #       modules = [ ];
  #     };
  #   };
  # };
  # configurationExtends = {
  #   nixos = final: prev: name: {
  #     modules =
  #       prev.modules
  #       ++ [
  #         listedArgs.nixosConfigurations.${name}
  #         or abort
  #         "The nixos configuration '${name}' is missing in 'nixos/configurations/'."
  #       ];
  #   };
  #   container = final: prev: name: {
  #     modules =
  #       prev.modules
  #       ++ [
  #         listedArgs.containerConfigurations.${name}
  #         or abort
  #         "The container configuration '${name}' is missing in 'container/configurations/'."
  #       ];
  #   };
  #   home = final: prev: name: {
  #     users = username: {
  #       modules =
  #         prev.modules
  #         ++ [
  #           listedArgs.homeConfigurations."${name}_${username}"
  #           or abort
  #           "The home configuration '${name}' is missing a user configuration for '${username}' in 'home/configurations/${name}/'."
  #         ];
  #     };
  #   };
  # };
  # args = map (name:
  #   defaultUpdateExtend
  #   configurationDefaults.${name}
  #   rawArgs."${name}Configurations" or { }
  #   configurationExtends.${name} or (_:_: { }))
  # (attrNames configurationDefaults);
in {
  inherit inputs name nixcfgs;
  outPath = path;
}
