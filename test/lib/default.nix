{
  lib,
  nixpkgs,
}: let
  foo = lib.mkNixcfg {
    name = "foo";
    path = ./nixcfg-foo;
    inputs = { self = foo; };
  };
  bar = lib.mkNixcfg {
    name = "bar";
    path = ./nixcfg-bar;
    inputs = {
      self = bar;
      nixcfg-foo = foo;
    };
  };
  baz = lib.mkNixcfg {
    name = "baz";
    path = ./nixcfg-baz;
    inputs = {
      self = baz;
      nixcfg-bar = bar;
      nixcfg-foo = foo;
    };
  };

  inherit ((
      import
      (
        let
          lock = lib.fromJSON (lib.readFile ./flake.lock);
        in
          lib.fetchTarball {
            url = "https://github.com/edolstra/flake-compat/archive/${lock.nodes.flake-compat.locked.rev}.tar.gz";
            sha256 = lock.nodes.flake-compat.locked.narHash;
          }
      )
      { src = ./.; }
    )
    .defaultNix)
    inputs
    ;

  exampleWith = attrs: let
    self = lib.mkNixcfg (let
      attrs' =
        {
          name = "example";
          path = ./nixcfg;
          inherit inputs;
        }
        // attrs;
    in
      attrs'
      // {
        inputs =
          attrs'.inputs
          // {
            inherit self;
          };
      });
  in
    self;

  example = exampleWith { };

  fails = expr: !(lib.tryEval (lib.deepSeq expr expr)).success;

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
      expr = lib.listAttrs ./nixcfg {
        lib."overlay.nix" = "libOverlay";
        pkgs."overlay.nix" = "overlay";
        nixos.configs = "nixosConfigurations";
        nixos.modules = "nixosModules";
        nixos.profiles = "nixosProfiles";
        home.configs = "homeConfigurations";
      };
      expected = {
        libOverlay = ./nixcfg/lib/overlay.nix;
        nixosConfigurations = {
          hello = ./nixcfg/nixos/configs/hello.nix;
          ubuntu = ./nixcfg/nixos/configs/ubuntu;
        };
        nixosModules = {
          test = ./nixcfg/nixos/modules/test.nix;
        };
        nixosProfiles = {
          base = ./nixcfg/nixos/profiles/base.nix;
        };
        homeConfigurations = {
          ubuntu_matthijs = ./nixcfg/home/configs/ubuntu/matthijs.nix;
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

    testUpdateWithDefaults = {
      expr =
        lib.defaultUpdateExtend (_: {
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
      expr = lib.catAttrs "name" baz.nixcfgs;
      expected = [ "foo" "bar" "baz" ];
    };

    testBazInputsOutPath = {
      expr = lib.all (input: input ? outPath) (lib.attrValues baz.inputs);
      expected = true;
    };

    testRequiredInputHomeManager = {
      expr = let example = exampleWith { inputs = { }; }; in fails example.homeConfigurations;
      expected = true;
    };

    testNixosConfigurationsArgs = {
      expr = example.nixosConfigurationsArgs;
      expected = {
        hello = {
          channelName = "nixpkgs";
          inputs = { };
          moduleArgs = { };
          modules = [ ./nixcfg/nixos/configs/hello.nix ];
          stateVersion = "22.11";
          system = "x86_64-linux";
        };
        ubuntu = {
          channelName = "nixpkgs";
          inputs = { };
          moduleArgs = { };
          modules = [ ./nixcfg/nixos/configs/ubuntu ];
          stateVersion = "22.11";
          system = "x86_64-linux";
        };
      };
    };

    testHomeConfigurationsInputs = {
      expr = let
        example = exampleWith {
          homeConfigurations.ubuntu.inputs = { inherit (inputs) home-manager; };
        };
      in
        example.homeConfigurationsArgs;
      expected = {
        ubuntu = {
          channelName = "nixpkgs";
          inputs = { inherit (inputs) home-manager; };
          moduleArgs = { };
          stateVersion = "22.11";
          system = "x86_64-linux";
          users = { };
        };
      };
    };

    testHomeInvalidOptions = {
      expr = let
        example = exampleWith {
          homeConfigurations.ubuntu = {
            stateVersion = "21.11";
          };
        };
      in
        fails example.homeConfigurationsArgs;
      expected = true;
    };

    testNixcfgsLib_1 = {
      expr = let
        inherit (example) lib;
      in
        (lib.lib.input.outPath or null) == inputs.nixpkgs.outPath && lib ? mkNixcfg;
      expected = true;
    };

    testNixcfgsLib_2 = {
      expr = let
        example = exampleWith {
          lib.channelName = "foo";
        };
        inherit (example) lib;
      in
        fails (lib.lib ? input);
      expected = true;
    };

    testNixcfgsLib_3 = {
      expr = let
        inherit (example) lib;
      in
        lib.overlay or null == true;
      expected = true;
    };

    testNixosConfigurations = {
      expr = example.nixosConfigurations.ubuntu.config.system.build ? toplevel;
      expected = true;
    };

    testChannels_1 = {
      expr = let
        example = exampleWith {
          channels.nixpkgs2 = {
            input = inputs.nixpkgs;
            overlays = [ (final: prev: { overlay2 = true; }) ];
          };
          nixosConfigurations.ubuntu.channelName = "nixpkgs2";
          homeConfigurations.ubuntu.channelName = "nixpkgs2";
        };
      in
        example.nixosConfigurations.ubuntu.pkgs ? overlay2;
      expected = true;
    };

    testChannels_2 = {
      expr = let
        example = exampleWith {
          channels.nixpkgs = {
            config = { allowUnfree = false; };
          };
        };
      in
        fails example.nixosConfigurations.ubuntu.pkgs.vscode.outPath;
      expected = true;
    };

    testContainerConfigurationsArgs = {
      expr = example.containerConfigurationsArgs;
      expected = {
        hello = {
          channelName = "nixpkgs";
          inputs = { };
          moduleArgs = { };
          modules = [ ./nixcfg/container/configs/hello.nix ];
          stateVersion = "22.11";
          system = "x86_64-linux";
        };
      };
    };

    testInvalidConfigurationSystem = {
      expr = let
        example = exampleWith {
          systems = [ "aarch64-linux" ];
          nixosConfigurations.ubuntu.system = "x86_64-linux";
        };
      in
        fails example.nixosConfigurationsArgs.ubuntu;
      expected = true;
    };

    testHomeConfigurations = {
      expr = example.homeConfigurations.ubuntu_matthijs ? activationPackage;
      expected = true;
    };

    testDefaultNixpkgs_1 = {
      expr = example.homeConfigurations.ubuntu_matthijs.pkgs.input.outPath == inputs.nixpkgs.outPath;
      expected = true;
    };

    testDefaultNixpkgs_2 = {
      expr = let
        example = exampleWith {
          inputs = removeAttrs inputs [ "nixpkgs" ];
        };
        nixpkgsOutPath = example.homeConfigurations.ubuntu_matthijs.pkgs.input.outPath;
      in {
        isStableNixpkgs = nixpkgsOutPath == inputs.nixos-22_11.outPath;
        isNixcfgNixpkgs = nixpkgsOutPath == nixpkgs.outPath;
      };
      expected = {
        isStableNixpkgs = true;
        isNixcfgNixpkgs = false;
      };
    };

    testDefaultNixpkgs_3 = {
      expr = let
        example = exampleWith {
          inputs = removeAttrs inputs [ "nixpkgs" "nixos-22_11" "nixos-unstable" ];
        };
        nixpkgsOutPath = example.homeConfigurations.ubuntu_matthijs.pkgs.input.outPath;
      in
        nixpkgsOutPath == nixpkgs.outPath;
      expected = true;
    };

    testContainerNoNixos_1 = {
      expr = let
        example = exampleWith {
          containerConfigurations.foo = { };
        };
      in
        fails example.containerConfigurationsArgs.foo;
      expected = true;
    };

    testContainerNoNixos_2 = {
      expr = example.nixosConfigurations ? hello;
      expected = false;
    };

    testNoConfigFile_1 = {
      expr = let
        example = exampleWith {
          nixosConfigurations.nofile = { };
        };
      in
        fails example.nixosConfigurationsArgs.nofile;
      expected = true;
    };

    testNoConfigFile_2 = {
      expr = let
        example = exampleWith {
          nixosConfigurations.nofile = {
            modules = [ { } ];
          };
        };
      in
        example.nixosConfigurations ? nofile;
      expected = true;
    };

    testOverlays = {
      expr = let
        example = exampleWith {
          overlays = { foo = final: prev: { overlay = true; }; };
          channels.nixpkgs = {
            overlays = overlays: [ overlays.example.foo ];
          };
        };
      in
        example.nixosConfigurations.ubuntu.pkgs ? overlay;
      expected = true;
    };

    testBaseProfile = {
      expr = example.nixosConfigurations.ubuntu.config.lib ? base;
      expected = true;
    };

    testContainerNixpkgs = {
      expr = let
        example = exampleWith {
          inputs = removeAttrs inputs [ "nixos-unstable" ];
        };
      in
        fails (example.containerConfigurations ? hello);
      expected = true;
    };

    testInputsPrime = {
      expr = let
        example = exampleWith {
          nixosConfigurations.ubuntu.modules = [
            ({ inputs', ... }: { lib.tests.test = inputs' ? nixpkgs.legacyPackages.hello; })
          ];
        };
      in
        example.nixosConfigurations.ubuntu.config.lib.tests.test;
      expected = true;
    };
  };
in
  lib.runTests tests
