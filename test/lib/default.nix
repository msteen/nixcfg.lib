{
  lib,
  nixcfg,
  nixpkgs,
}: let
  foo = lib.mkNixcfg {
    name = "foo";
    path = ./nixcfg-foo;
    sources = { };
  };
  bar = lib.mkNixcfg {
    name = "bar";
    path = ./nixcfg-bar;
    sources = { };
  };
  baz = lib.mkNixcfg {
    name = "baz";
    path = ./nixcfg-baz;
    sources = {
      nixcfg-foo = foo;
      nixcfg-bar = bar;
    };
    nixcfgs = [ foo bar ];
  };

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
          sources = { };
          channelName = "nixpkgs";
          system = "x86_64-linux";
          moduleArgs = { };
          stateVersion = "22.11";
          users = _: {
            modules = [ ];
          };
        }) {
          ubuntu = {
            inherit (bar.config) sources;
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
          inherit (bar.config) sources;
          channelName = "nixos-22_11";
          system = "x86_64-linux";
          moduleArgs = { };
          stateVersion = "22.11";
          users.matthijs.modules = [ testListAttrs.expected.homeConfigurations.ubuntu_matthijs ];
        };
      };
    };

    testFooName = {
      expr = foo.config.name;
      expected = "foo";
    };

    testBazNixcfgsOrder = {
      expr = lib.mapGetAttrPath [ "config" "name" ] baz.nixcfgs;
      expected = [ "foo" "bar" "baz" ];
    };

    testRequiredSourceHomeManager = {
      expr = let example = exampleWith { sources = { }; }; in fails example.configurations.home;
      expected = true;
    };

    testNixosConfigurationsConfig = {
      expr = example.config.nixosConfigurations;
      expected = {
        hello = {
          channelName = "nixpkgs";
          sources = { };
          moduleArgs = { };
          modules = [ ./nixcfg/nixos/configs/hello.nix ];
          stateVersion = "22.11";
          system = "x86_64-linux";
        };
        ubuntu = {
          channelName = "nixpkgs";
          sources = { };
          moduleArgs = { };
          modules = [ ./nixcfg/nixos/configs/ubuntu ];
          stateVersion = "22.11";
          system = "x86_64-linux";
        };
      };
    };

    testHomeConfigurationsSources = {
      expr = let
        example = exampleWith {
          homeConfigurations.ubuntu.sources = { inherit (sources) home-manager; };
        };
      in
        example.config.homeConfigurations;
      expected = {
        ubuntu = {
          channelName = "nixpkgs";
          sources = { inherit (sources) home-manager; };
          moduleArgs = { };
          stateVersion = "22.11";
          system = "x86_64-linux";
          users.matthijs = {
            homeDirectory = "/home/matthijs";
            modules = [ ./nixcfg/home/configs/ubuntu/matthijs.nix ];
          };
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
        fails example.config.homeConfigurations;
      expected = true;
    };

    testNixcfgsLib_1 = {
      expr = example.lib ? overlay;
      expected = true;
    };

    testNixcfgsLib_2 = {
      expr = let
        example = exampleWith {
          lib.channelName = "foo";
        };
        inherit (example) lib;
      in
        fails (lib.lib ? source);
      expected = true;
    };

    testNixcfgsLib_3 = {
      expr = let
        inherit (example) lib;
      in
        (lib.lib.source or null) == sources.nixpkgs && lib ? mkNixcfg;
      expected = true;
    };

    testNixcfgsLib_4 = {
      expr = let
        example = exampleWith {
          lib = {
            channelName = "nixos-unstable";
            overlays = [ (final: prev: { test = prev.lib.source or null == sources.nixos-unstable; }) ];
          };
        };
      in
        example.lib.test;
      expected = true;
    };

    testNixosConfigurations = {
      expr = example.configurations.nixos.ubuntu.config.system.build ? toplevel;
      expected = true;
    };

    testChannels_1 = {
      expr = let
        example = exampleWith {
          channels.nixpkgs2 = {
            source = sources.nixpkgs;
            overlays = [ (final: prev: { overlay2 = true; }) ];
          };
          nixosConfigurations.ubuntu.channelName = "nixpkgs2";
          homeConfigurations.ubuntu.channelName = "nixpkgs2";
        };
      in
        example.configurations.nixos.ubuntu.pkgs ? overlay2;
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
        fails example.configurations.nixos.ubuntu.pkgs.vscode.outPath;
      expected = true;
    };

    testChannels_3 = {
      expr = let
        example = exampleWith {
          overlays.default = final: prev: { test = true; };
        };
      in
        example.configurations.nixos.ubuntu.pkgs ? test;
      expected = true;
    };

    testContainerConfigurationsArgs = {
      expr = example.config.containerConfigurations;
      expected = {
        hello = {
          channelName = "nixpkgs";
          sources = { };
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
        fails example.config.nixosConfigurations.ubuntu;
      expected = true;
    };

    testHomeConfigurations = {
      expr = example.configurations.home.ubuntu_matthijs ? activationPackage;
      expected = true;
    };

    testDefaultNixpkgs_1 = {
      expr = toString example.configurations.home.ubuntu_matthijs.pkgs.path == sources.nixpkgs;
      expected = true;
    };

    testDefaultNixpkgs_2 = {
      expr = let
        example = exampleWith {
          sources = removeAttrs sources [ "nixpkgs" ];
        };
        pkgsPath = toString example.configurations.home.ubuntu_matthijs.pkgs.path;
      in {
        isStableNixpkgs = pkgsPath == sources.nixos-22_11;
        isNixcfgNixpkgs = pkgsPath == nixpkgs;
      };
      expected = {
        isStableNixpkgs = true;
        isNixcfgNixpkgs = false;
      };
    };

    testDefaultNixpkgs_3 = {
      expr = let
        example = exampleWith {
          sources = removeAttrs sources [ "nixpkgs" "nixos-22_11" "nixos-unstable" ];
        };
        pkgsPath = toString example.configurations.home.ubuntu_matthijs.pkgs.path;
      in
        pkgsPath == nixpkgs;
      expected = true;
    };

    testContainerNoNixos_1 = {
      expr = let
        example = exampleWith {
          containerConfigurations.foo = { };
        };
      in
        fails example.config.containerConfigurations.foo;
      expected = true;
    };

    testContainerNoNixos_2 = {
      expr = example.configurations.nixos ? hello;
      expected = false;
    };

    testNoConfigFile_1 = {
      expr = let
        example = exampleWith {
          nixosConfigurations.nofile = { };
        };
      in
        fails example.config.nixosConfigurations.nofile;
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
        example.configurations.nixos ? nofile;
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
        example.configurations.nixos.ubuntu.pkgs ? overlay;
      expected = true;
    };

    testBaseProfile_1 = {
      expr = example.configurations.nixos.ubuntu.config.lib ? base;
      expected = true;
    };

    testBaseProfile_2 = {
      expr = example.configurations.container.hello.config.containers.hello.config.lib ? base;
      expected = true;
    };

    testContainerNixpkgs = {
      expr = let
        example = exampleWith {
          sources = removeAttrs sources [ "nixos-unstable" ];
        };
      in
        fails (example.configurations.container ? hello);
      expected = true;
    };
  };
in
  lib.runTests tests
