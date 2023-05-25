{ lib }: let
  tests = rec {
    testConcatAttrs = {
      expr = lib.concatAttrs [ { foo = 1; } { bar = 2; } { foo = 3; } ];
      expected = {
        foo = 3;
        bar = 2;
      };
    };

    testConcatAttrsRecursive = {
      expr = lib.concatAttrsRecursive [
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
        lib.extendsList [
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
      expr = lib.listAttrs ./list-attrs {
        lib."overlay.nix" = "libOverlay";
        pkgs."overlay.nix" = "overlay";
        nixos.configs = "nixosConfigurations";
        nixos.modules = "nixosModules";
        nixos.profiles = "nixosProfiles";
        home.configs = "homeConfigurations";
      };
      expected = {
        libOverlay = ./list-attrs/lib/overlay.nix;
        nixosConfigurations = {
          ubuntu = ./list-attrs/nixos/configs/ubuntu;
        };
        nixosModules = { };
        nixosProfiles = { };
        homeConfigurations = {
          ubuntu_matthijs = ./list-attrs/home/configs/ubuntu/matthijs.nix;
        };
      };
    };

    testApplyAttrs_1 = {
      expr =
        lib.applyAttrs (name: {
          users = username: {
            bar = 1;
          };
        }) {
          ubuntu.users.matthijs.baz = 2;
        };
      expected = {
        ubuntu.users.matthijs.bar = 1;
      };
    };

    testApplyAttrs_2 = {
      expr =
        lib.applyAttrs (name: {
          users = username: {
            modules = [ testListAttrs.expected.homeConfigurations."${name}_${username}" ];
          };
        }) {
          ubuntu.users.matthijs.stateVersion = "21.11";
        };
      expected = {
        ubuntu.users.matthijs.modules = [ testListAttrs.expected.homeConfigurations.ubuntu_matthijs ];
      };
    };

    testApplyAttrs_3 = {
      expr =
        lib.applyAttrs (name: {
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
  };
in
  lib.evalTests tests
