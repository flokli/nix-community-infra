{ pkgs, lib, config, ... }:

let
  userLib = import ../users/lib.nix { inherit lib; };

  sources = import ../nix/sources.nix;
  nixpkgs-update = import sources.nixpkgs-update { returnShellEnv = false; };
  nixpkgsUpdateSystemDependencies = with pkgs; [
    nix
    git
    getent
    gitAndTools.hub
    jq
    tree
    gist
    cachix
    curl
  ];

  nixpkgs-update-github-releases = "${sources.nixpkgs-update-github-releases}/main.py";

  nixpkgsUpdateServiceConfigCommon = {
    Type = "oneshot";
    User = "r-ryantm";
    Group = "r-ryantm";
    WorkingDirectory = "/var/lib/nixpkgs-update";
    StateDirectory = "nixpkgs-update";
    StateDirectoryMode = "700";
    CacheDirectory = "nixpkgs-update";
    CacheDirectoryMode = "700";
    LogsDirectory = "nixpkgs-update";
    LogsDirectoryMode = "755";
    StandardOutput = "journal";
  };
in
{
  users.users.r-ryantm.packages = [ pkgs.cachix ];
  users.groups.r-ryantm = {};
  users.users.r-ryantm = {
    useDefaultShell = true;
    isNormalUser = true; # The hub cli seems to really want stuff to be set up like a normal user
    uid = userLib.mkUid "rrtm";
    extraGroups = [ "r-ryantm" ];
  };
  nix.trustedUsers = [
    "r-ryantm"
  ];

  systemd.services.nixpkgs-update = {
    description = "nixpkgs-update service";
    enable = true;
    restartIfChanged = false;
    path = nixpkgsUpdateSystemDependencies;
    environment.XDG_CONFIG_HOME = "/var/lib/nixpkgs-update";
    environment.XDG_CACHE_HOME = "/var/cache/nixpkgs-update";
    # API_TOKEN is used by nixpkgs-update-github-releases
    environment.API_TOKEN_FILE = "/var/lib/nixpkgs-update/github_token_with_username.txt";
    # Used by nixpkgs-update-github-releases to install python dependencies
    environment.NIX_PATH = "nixpkgs=${sources.nixpkgs}";

    serviceConfig = nixpkgsUpdateServiceConfigCommon;
    script = ''
      ${nixpkgs-update}/bin/nixpkgs-update delete-done
      ${nixpkgs-update-github-releases} > /var/lib/nixpkgs-update/packages-to-update.txt
      ${nixpkgs-update}/bin/nixpkgs-update update-list --cachix --outpaths
      ${nixpkgs-update}/bin/nixpkgs-update delete-done
      ${nixpkgs-update}/bin/nixpkgs-update fetch-repology > /var/lib/nixpkgs-update/packages-to-update.txt
      ${nixpkgs-update}/bin/nixpkgs-update update-list --cachix --outpaths
    '';
  };

  systemd.timers.nixpkgs-update = {
    description = "nixpkgs-update";
    enable = true;
    timerConfig = { OnCalendar = "daily"; };
  };

  services.nginx.virtualHosts."r.ryantm.com" = {
    forceSSL = true;
    enableACME = true;
    locations."/log/" = {
      alias = "/var/log/nixpkgs-update/";
      extraConfig = "autoindex on;";
    };
  };

}
