{
  nixpkgs,
  nixcfg,
}: let
  inherit (builtins)
    all
    attrValues
    catAttrs
    deepSeq
    fromJSON
    getFlake
    mapAttrs
    readFile
    trace
    tryEval
    ;
  inherit (nixpkgs.lib)
    runTests
    ;
  inherit (nixcfg.lib)
    applyAttrs
    concatAttrs
    concatAttrsRecursive
    defaultUpdateExtend
    dummyNixosModule
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

  inherit ((
      import
      (
        let
          lock = builtins.fromJSON (builtins.readFile ./flake.lock);
        in
          fetchTarball {
            url = "https://github.com/edolstra/flake-compat/archive/${lock.nodes.flake-compat.locked.rev}.tar.gz";
            sha256 = lock.nodes.flake-compat.locked.narHash;
          }
      )
      { src = ./.; }
    )
    .defaultNix)
    inputs
    ;

  fails = expr: !(tryEval (deepSeq expr expr)).success;

  tests = rec {
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
        nixos.configs = "nixosConfigurations";
        nixos.modules = "nixosModules";
        nixos.profiles = "nixosProfiles";
        home.configs = "homeConfigurations";
      };
      expected = {
        libOverlay = ./nixcfg/lib/overlay.nix;
        nixosConfigurations = {
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
      in
        fails self.homeConfigurations;
      expected = true;
    };

    testNixosConfigurationsArgs = {
      expr = let
        self = mkNixcfg {
          name = "example";
          path = ./nixcfg;
          inputs = {
            inherit self;
          };
        };
      in
        self.nixosConfigurationsArgs;
      expected = {
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
        self = mkNixcfg {
          name = "example";
          path = ./nixcfg;
          inputs = {
            inherit self;
          };
          homeConfigurations.ubuntu.inputs = {
            inherit (inputs) home-manager;
          };
        };
      in
        self.homeConfigurationsArgs;
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
      in
        fails self.homeConfigurationsArgs;
      expected = true;
    };

    testNixcfgsLib_1 = {
      expr = let
        self = mkNixcfg {
          name = "example";
          path = ./nixcfg;
          inputs = {
            inherit self;
            inherit (inputs) home-manager;
          };
        };
        inherit (self) lib;
      in
        (lib.lib.input.outPath or null) == nixpkgs.outPath && lib ? mkNixcfg;
      expected = true;
    };

    testNixcfgsLib_2 = {
      expr = let
        self = mkNixcfg {
          name = "example";
          path = ./nixcfg;
          inputs = {
            inherit self;
            inherit (inputs) home-manager;
          };
          lib.channelName = "foo";
        };
        inherit (self) lib;
      in
        fails (lib.lib ? input);
      expected = true;
    };

    testNixcfgsLib_3 = {
      expr = let
        self = mkNixcfg {
          name = "example";
          path = ./nixcfg;
          inputs = {
            inherit self;
            inherit (inputs) home-manager;
          };
        };
        inherit (self) lib;
      in
        lib.overlay or null == true;
      expected = true;
    };

    testNixosConfigurations = {
      expr = let
        self = mkNixcfg {
          name = "example";
          path = ./nixcfg;
          inputs = {
            inherit self;
            inherit (inputs) home-manager nixpkgs;
          };
        };
      in
        self.nixosConfigurations.x86_64-linux.ubuntu.config.system.build ? toplevel;
      expected = true;
    };

    testChannels_1 = {
      expr = let
        self = mkNixcfg {
          name = "example";
          path = ./nixcfg;
          inputs = {
            inherit self;
            inherit (inputs) home-manager nixpkgs;
          };
          channels.nixpkgs2 = {
            input = inputs.nixpkgs;
            overlays = [ (final: prev: { overlay2 = true; }) ];
          };
          nixosConfigurations.ubuntu.channelName = "nixpkgs2";
          homeConfigurations.ubuntu.channelName = "nixpkgs2";
        };
      in
        self.nixosConfigurations.x86_64-linux.ubuntu.pkgs ? overlay2;
      expected = true;
    };

    testChannels_2 = {
      expr = let
        self = mkNixcfg {
          name = "example";
          path = ./nixcfg;
          inputs = {
            inherit self;
            inherit (inputs) home-manager nixpkgs;
          };
          channels.nixpkgs = {
            config = { allowUnfree = false; };
          };
        };
      in
        fails self.nixosConfigurations.x86_64-linux.ubuntu.pkgs.vscode.outPath;
      expected = true;
    };

    testContainerConfigurationsArgs = {
      expr = let
        self = mkNixcfg {
          name = "example";
          path = ./nixcfg;
          inputs = {
            inherit self;
            inherit (inputs) extra-container;
          };
        };
      in
        self.containerConfigurationsArgs;
      expected = {
        hello = {
          channelName = "nixpkgs";
          inputs = { };
          moduleArgs = { };
          modules = {
            container = [ ./nixcfg/container/configs/hello/container.nix ];
            nixos = [ ./nixcfg/container/configs/hello/nixos.nix ];
          };
          stateVersion = "22.11";
          system = "x86_64-linux";
        };
      };
    };

    testInvalidConfigurationSystem = {
      expr = let
        self = mkNixcfg {
          name = "example";
          path = ./nixcfg;
          inputs = {
            inherit self;
          };
          systems = [ "aarch64-linux" ];
          nixosConfigurations.ubuntu.system = "x86_64-linux";
        };
      in
        fails self.nixosConfigurationsArgs.ubuntu;
      expected = true;
    };

    testHomeConfigurations = {
      expr = let
        self = mkNixcfg {
          name = "example";
          path = ./nixcfg;
          inputs =
            inputs
            // {
              inherit self;
            };
        };
      in
        self.homeConfigurations.x86_64-linux.ubuntu_matthijs ? activationPackage;
      expected = true;
    };

    testDefaultNixpkgs_1 = {
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
        self.homeConfigurations.x86_64-linux.ubuntu_matthijs.pkgs.input.outPath == nixpkgs.outPath;
      expected = true;
    };

    testDefaultNixpkgs_2 = {
      expr = let
        nixos-22_11 = inputs.nixos-unstable;
        self = mkNixcfg {
          name = "example";
          path = ./nixcfg;
          inputs = {
            inherit nixos-22_11 self;
            inherit (inputs) home-manager;
          };
        };
        nixpkgsOutPath = self.homeConfigurations.x86_64-linux.ubuntu_matthijs.pkgs.input.outPath;
      in
        nixpkgsOutPath == nixos-22_11.outPath && nixpkgsOutPath != nixpkgs.outPath;
      expected = true;
    };

    testNixosContainerNoOverlap = {
      expr = let
        self = mkNixcfg {
          name = "example";
          path = ./nixcfg;
          inputs =
            inputs
            // {
              inherit self;
            };
          nixosConfigurations.hello = { };
        };
      in
        fails self.nixosConfigurationsArgs.hello;
      expected = true;
    };

    testNoConfigFile_1 = {
      expr = let
        self = mkNixcfg {
          name = "example";
          path = ./nixcfg;
          inputs =
            inputs
            // {
              inherit self;
            };
          nixosConfigurations.nofile = { };
        };
      in
        fails self.nixosConfigurationsArgs.nofile;
      expected = true;
    };

    testNoConfigFile_2 = {
      expr = let
        self = mkNixcfg {
          name = "example";
          path = ./nixcfg;
          inputs =
            inputs
            // {
              inherit self;
            };
          nixosConfigurations.nofile = {
            modules = [ { } ];
          };
        };
      in
        self.nixosConfigurations.x86_64-linux ? nofile;
      expected = true;
    };

    testOverlays = {
      expr = let
        self = mkNixcfg {
          name = "example";
          path = ./nixcfg;
          inputs =
            inputs
            // {
              inherit self;
            };
          overlays = { foo = final: prev: { overlay = true; }; };
          channels.nixpkgs = {
            overlays = overlays: [ overlays.example.foo ];
          };
        };
      in
        self.nixosConfigurations.x86_64-linux.ubuntu.pkgs ? overlay;
      expected = true;
    };

    testBaseProfile = {
      expr = let
        self = mkNixcfg {
          name = "example";
          path = ./nixcfg;
          inputs =
            inputs
            // {
              inherit self;
            };
        };
      in
        self.nixosConfigurations.x86_64-linux.ubuntu.config.lib ? base;
      expected = true;
    };

    testContainerNixpkgs = {
      expr = let
        self = mkNixcfg {
          name = "example";
          path = ./nixcfg;
          inputs = {
            inherit self;
            inherit (inputs) extra-container;
          };
        };
      in
        fails (self.containerConfigurations.x86_64-linux ? hello);
      expected = true;
    };
  };
in
  runTests tests
