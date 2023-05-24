{
  self,
  lib,
}: let
  inherit (lib) types;
in {
  evalModulesToConfig = modules: (lib.evalModules { inherit modules; }).config;

  optionsToSubmodule = options:
    types.submodule (
      if lib.isFunction options
      then
        { name, ... }: {
          options = options name;
        }
      else {
        inherit options;
      }
    );
}
