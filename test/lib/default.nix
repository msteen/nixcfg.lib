{
  nixpkgs,
  nixcfg,
}: let
  inherit
    (builtins)
    all
    attrValues
    catAttrs
    deepSeq
    fromJSON
    getFlake
    readFile
    tryEval
    ;
  inherit (nixpkgs.lib) runTests;
  inherit
    (nixcfg.lib)
    applyAttrs
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

  inputs = fromJSON (readFile ./flake.json);
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
      expr = listAttrs ./nixcfg {
        lib."overlay.nix" = "libOverlay";
        pkgs."overlay.nix" = "overlay";
        nixos.configurations = "nixosConfigurations";
        nixos.modules = "nixosModules";
        nixos.profiles = "nixosProfiles";
        home.configurations = "homeConfigurations";
      };
      expected = {
        libOverlay = ./nixcfg/lib/overlay.nix;
        nixosConfigurations = {
          ubuntu = ./nixcfg/nixos/configurations/ubuntu;
        };
        nixosModules = {
          test = ./nixcfg/nixos/modules/test.nix;
        };
        nixosProfiles = { };
        homeConfigurations = {
          ubuntu_matthijs = ./nixcfg/home/configurations/ubuntu/matthijs.nix;
          macbook = ./nixcfg/home/configurations/macbook.nix;
        };
      };
    };

    testApplyAttrs_1 = {
      expr =
        applyAttrs (name: {
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
        applyAttrs (name: {
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
        applyAttrs (name: {
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
        defaultUpdateExtend (_: {
          inputs = { };
          channelName = "nixpkgs";
          system = "x86_64-linux";
          moduleArgs = { };
          stateVersion = "22.11";
          users = _: {
            modules = [ ];
          };
        }) {
          ubuntu = {
            inherit (bar) inputs;
            channelName = "nixos-22_11";
            users.matthijs = { };
          };
        } (final: prev: name: {
          users = username: {
            modules =
              prev.${name}.users.${username}.modules
              ++ [ testListAttrs.expected.homeConfigurations."${name}_${username}" ];
          };
        });
      expected = {
        ubuntu = {
          inherit (bar) inputs;
          channelName = "nixos-22_11";
          system = "x86_64-linux";
          moduleArgs = { };
          stateVersion = "22.11";
          users.matthijs.modules = [ testListAttrs.expected.homeConfigurations.ubuntu_matthijs ];
        };
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

    testRequiredInputHomeManager = {
      expr = let
        self = mkNixcfg {
          name = "example";
          path = ./nixcfg;
          inputs = {
            inherit self;
          };
        };
        expr = self.homeConfigurationsArgs;
      in
        tryEval (deepSeq expr expr);
      expected = {
        success = false;
        value = false;
      };
    };

    testNixosConfigurationsArgs = {
      expr = let
        self = mkNixcfg {
          name = "example";
          path = ./nixcfg;
          inputs = {
            inherit self;
            inherit (inputs) home-manager;
          };
        };
      in
        self.nixosConfigurationsArgs;
      expected = {
        ubuntu = {
          channelName = "nixpkgs";
          inputs = { };
          moduleArgs = { };
          modules = [ ./nixcfg/nixos/configurations/ubuntu ];
          stateVersion = "22.11";
          system = "x86_64-linux";
        };
      };
    };

    testHomeInvalidOptions = {
      expr = let
        self = mkNixcfg {
          name = "example";
          path = ./nixcfg;
          inputs = {
            inherit self;
            inherit (inputs) home-manager;
          };
          homeConfigurations.ubuntu = {
            stateVersion = "21.11";
          };
        };
        expr = self.homeConfigurationsArgs;
      in
        tryEval (deepSeq expr expr);
      expected = {
        success = false;
        value = false;
      };
    };
  }
