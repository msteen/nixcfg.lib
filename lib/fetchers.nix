{
  self,
  lib,
}: {
  fetchNixpkgsPull = id: sha256:
    lib.fetchurl {
      url = "https://github.com/NixOS/nixpkgs/pull/${toString id}.diff";
      inherit sha256;
    };
}
