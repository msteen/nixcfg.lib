{
  self,
  lib,
}: {
  dummyNixosModule = {
    boot.loader.grub.enable = false;
    fileSystems."/".device = "/dev/null";
  };
}
