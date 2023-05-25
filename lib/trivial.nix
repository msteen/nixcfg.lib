{
  self,
  lib,
}: {
  inherit lib;

  dummyNixosModule = {
    boot.loader.grub.enable = false;
    fileSystems."/".device = "/dev/null";
  };
}
