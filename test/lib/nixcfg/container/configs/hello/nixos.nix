{ pkgs, ... }: let
  inherit (builtins) attrValues;
in {
  systemd.services.hello = {
    path = attrValues { inherit (pkgs) netcat; };
    script = ''
      while true; do
        echo hello | nc -lN 50
      done
    '';
    wantedBy = [ "multi-user.target" ];
  };
}
