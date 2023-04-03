{
  nixpkgs,
  nixcfg,
}: let
  inherit (builtins) all attrValues catAttrs;
  inherit (nixpkgs.lib) runTests;
  inherit
    (nixcfg.lib)
    callableUpdate
    concatAttrs
    concatAttrsRecursive
    defaultUpdateExtend
    extendsList
    listAttrs
    mkNixcfg
    ;

  foo = mkNixcfg {
    name = "foo";
    path = ./nixcfg-foo;
    inputs = { self = foo; };
  };
  bar = mkNixcfg {
    name = "bar";
    path = ./nixcfg-bar;
    inputs = {
      self = bar;
      nixcfg-foo = foo;
    };
  };
  baz = mkNixcfg {
    name = "baz";
    path = ./nixcfg-baz;
    inputs = {
      self = baz;
      nixcfg-bar = bar;
      nixcfg-foo = foo;
    };
  };
in
  runTests rec {
    testConcatAttrs = {
      expr = concatAttrs [ { foo = 1; } { bar = 2; } { foo = 3; } ];
      expected = {
        foo = 3;
        bar = 2;
      };
    };

    testConcatAttrsRecursive = {
      expr = concatAttrsRecursive [
        { foo = { a = 1; }; }
        { bar = 2; }
        {
          foo = {
            a = 3;
            b = 4;
          };
        }
      ];
      expected = {
        foo = {
          a = 3;
          b = 4;
        };
        bar = 2;
      };
    };

    testExtendsList = {
      expr =
        extendsList [
          (final: prev: { bar = prev.bar + "baz"; })
        ] (final: {
          foo = "foo" + final.bar;
          bar = "bar";
        });
      expected = {
        foo = "foobarbaz";
        bar = "barbaz";
      };
    };

    testListAttrs = {
      expr = listAttrs ./list-attrs {
        lib."overlay.nix" = "libOverlay";
        pkgs."overlay.nix" = "overlay";
        nixos.configurations = "nixosConfigurations";
        nixos.modules = "nixosModules";
        nixos.profiles = "nixosProfiles";
        home.configurations = "homeConfigurations";
      };
      expected = {
        libOverlay = ./list-attrs/lib/overlay.nix;
        nixosConfigurations = {
          test = ./list-attrs/nixos/configurations/test;
        };
        nixosModules = {
          test = ./list-attrs/nixos/modules/test.nix;
        };
        nixosProfiles = { };
        homeConfigurations = {
          ubuntu_matthijs = ./list-attrs/home/configurations/ubuntu/matthijs.nix;
          macbook = ./list-attrs/home/configurations/macbook.nix;
        };
      };
    };

    testCallableUpdate = {
      expr =
        callableUpdate (name: {
          users = username: {
            modules = [ testListAttrs.expected.homeConfigurations."${name}_${username}" ];
          };
        }) {
          ubuntu.users.matthijs = { };
        };
      expected = {
        ubuntu.users.matthijs.modules = [ testListAttrs.expected.homeConfigurations.ubuntu_matthijs ];
      };
    };

    testCallableUpdate_2 = {
      expr =
        callableUpdate
        (name: {
          users = username: {
            modules = [ testListAttrs.expected.homeConfigurations."${name}_${username}" ];
          };
        }) {
          ubuntu = { };
        };
      expected = {
        ubuntu.users = { };
      };
    };

    testUpdateWithDefaults = {
      expr =
        defaultUpdateExtend {
          inputs = { };
          channelName = "nixpkgs";
          system = "x86_64-linux";
          moduleArgs = { };
          stateVersion = "22.11";
          users = _: {
            modules = [ ];
          };
        } {
          inherit (bar) inputs;
          channelName = "nixos-22_11";
        } (final: prev: name: {
          users = username: {
            modules = prev.modules ++ [ testListAttrs.expected.homeConfigurations."${name}_${username}" ];
          };
        });
      expected = {
        inherit (bar) inputs;
        channelName = "nixos-22_11";
        system = "x86_64-linux";
        moduleArgs = { };
        stateVersion = "22.11";
        users.matthijs.modules = [ testListAttrs.expected.homeConfigurations.ubuntu_matthijs ];
      };
    };

    testFooName = {
      expr = foo.name;
      expected = "foo";
    };

    testBazNixcfgsOrder = {
      expr = catAttrs "name" baz.nixcfgs;
      expected = [ "foo" "bar" "baz" ];
    };

    testBazInputsOutPath = {
      expr = all (input: input ? outPath) (attrValues baz.inputs);
      expected = true;
    };
  }
