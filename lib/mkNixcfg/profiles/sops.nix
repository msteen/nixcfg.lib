{
  config,
  nixcfg,
  ...
}: let
  inherit (builtins) filter;
in {
  sops = {
    # FIXME: We probably want a systemd service that automatically generates the age key file based on our ssh key.
    # age.sshKeyPaths = map (x: x.path) (filter (x: x.type == "ed25519") config.services.openssh.hostKeys);
    # age.keyFile = "/var/lib/sops-nix/key.txt";
  };
}
