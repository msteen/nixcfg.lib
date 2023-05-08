{
  lib,
  nixcfg,
  pkgs,
}: let
  nmdSrc = fetchTarball {
    url = "https://git.sr.ht/~rycee/nmd/archive/abb15317ebd17e5a0a7dd105e2ce52f2700185a8.tar.gz";
    sha256 = "0zzrbjxf15hada279irif7s3sb8vs95jn4y4f8694as0j739gd1m";
  };

  nmd = import nmdSrc { inherit lib pkgs; };

  # Make sure the used package is scrubbed to avoid actually
  # instantiating derivations.
  scrubbedPkgsModule = {
    imports = [
      {
        _module.args = {
          pkgs = lib.mkForce (nmd.scrubDerivations "pkgs" pkgs);
          pkgs_i686 = lib.mkForce { };
        };
      }
    ];
  };

  buildModulesDocs = args:
    nmd.buildModulesDocs ({
        moduleRootPaths = [ ./../../.. ];
        mkModuleUrl = path: "https://github.com/msteen/nixcfg.lib/blob/master/${path}#blob-path";
        channelName = "nixcfg";
      }
      // args);

  hmModulesDocs = buildModulesDocs {
    modules = [
      (import ../modules/nixcfg.nix { inherit lib nixcfg; })
      scrubbedPkgsModule
    ];
    docBook.id = "nixcfg-options";
  };

  docs = nmd.buildDocBookDocs {
    pathName = "nixcfg";
    projectName = "Nix-related configurations";
    modulesDocs = [ hmModulesDocs ];
    documentsDirectory = ./.;
    documentType = "book";
    chunkToc = ''
      <toc>
        <d:tocentry xmlns:d="http://docbook.org/ns/docbook" linkend="book-nixcfg-manual"><?dbhtml filename="index.html"?>
          <d:tocentry linkend="ch-options"><?dbhtml filename="options.html"?></d:tocentry>
        </d:tocentry>
      </toc>
    '';
  };
in { inherit (docs) html htmlOpenTool; }
