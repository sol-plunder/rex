Here's an example of what Nix configurations could look like using
Rex notation.  This mostly don't try to take advantage of the nicer
features of Rex, and instead tries to stick as close as possible to
the Nix notation while still being valid Rex.

```nix
{ config, pkgs, lib, ... }:

let
  username = "alice";
  homeDir = "/home/${username}";
in {
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = "workstation";
  time.timeZone = "America/New_York";

  environment.systemPackages = with pkgs; [
    vim git curl wget htop ripgrep
  ];

  users.users.${username} = {
    isNormalUser = true;
    home = homeDir;
    extraGroups = [ "wheel" "networkmanager" "docker" ];
    shell = pkgs.zsh;
  };

  programs.zsh.shellInit = ''
    export EDITOR=vim
    export PATH="$HOME/.local/bin:$PATH"
  '';

  services.nginx.virtualHosts."example.local" = {
    root = "/var/www/example";
    extraConfig = ''
      location /api {
        proxy_pass http://localhost:8080;
      }
    '';
  };

  networking.firewall.allowedTCPPorts = [ 22 80 443 ];

  system.stateVersion = "24.05";
}
```

And here is a variant in rex notation:

```rexpr
{ config, pkgs, lib, ..._ }:
  username = 'alice
  homeDir = '/home/${username}
  {
    imports = [ './hardware-configuration.nix ];

    networking.hostName = 'workstation;
    time.timeZone = 'America/New_York;

    environment.systemPackages = (with pkgs; [
      vim git curl wget htop ripgrep
    ]);

    users.users.(${username}) = {
      isNormalUser = true;
      home = homeDir;
      extraGroups = [ 'wheel 'networkmanager 'docker ];
      shell = pkgs.zsh;
    };

    programs.zsh.shellInit = ''
      export EDITOR=vim
      export PATH="$HOME/.local/bin:$PATH"
    '';

    services.nginx.virtualHosts."example.local" = {
      root = '/var/www/example;
      extraConfig = ''
        location /api {
          proxy_pass http://localhost:8080;
        }
      '';
    };

    networking.firewall.allowedTCPPorts = [ 22 80 443 ];

    system.stateVersion = '24.05;
  }
```
