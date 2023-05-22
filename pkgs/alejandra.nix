{
  lib,
  rustPlatform,
  testVersion,
  src,
}:
rustPlatform.buildRustPackage {
  pname = "alejandra";
  version = "3.0.0-custom";
  inherit src;
  cargoLock.lockFile = src + "/Cargo.lock";

  passthru.tests = {
    version = testVersion { package = alejandra; };
  };

  meta = {
    description = "The Uncompromising Nix Code Formatter.";
    homepage = "https://github.com/kamadorueda/alejandra";
    license = lib.licenses.unlicense;
    maintainers = [ lib.maintainers.kamadorueda ];
    platforms = lib.systems.doubles.all;
  };
}
