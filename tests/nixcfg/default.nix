{
  lib,
  nixpkgs,
}: let
  inherit (lib.importFlake ./.) inputs;
  sources = lib.mapAttrs (_: input: input.outPath) inputs;

  exampleWith = attrs: let
    self = lib.mkNixcfg (let
      attrs' =
        {
          name = "example";
          path = ./nixcfg;
          inherit sources;
        }
        // attrs;
    in
      attrs'
      // {
        sources =
          attrs'.sources
          // {
            inherit self;
          };
      });
  in
    self;

  example = exampleWith { };

  # We cannot use `lib.fails` as `lib` might result in an error being thrown when shadowed.
  inherit (lib) fails;

  test = {
    nixcfg ? example,
    config,
    outputs,
    effects ? lib.const true,
  }: let
    config' = lib.getAttrsPattern config nixcfg.config;
    outputs' =
      if lib.isFunction outputs
      then outputs config'
      else outputs;
  in {
    config = config';
    outputs = outputs';
    result = lib.matchAttrsPattern outputs' nixcfg;
  };

  # TODO: Let function be you don't care about names.

  tests = [
    (test {
      config = { name = null; };
      outputs = config: {
        config = { inherit (config) name; };
        overlays.${name} = null;
        profiles.${name} = null;
      };
    })
  ];
in
  tests
