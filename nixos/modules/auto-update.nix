# Daily NixOS auto-update (switch-only, no automatic reboot)
#
# Runs `nixos-rebuild switch` against the PUBLIC timestone-tofu flake over
# https — no credentials on the node. Reboots are deliberate (the manual
# bin/cycle-node.sh path), so a bad update can never brick the host unattended:
# the new generation is active but the running kernel stays until the operator
# cycles. Rollback: nixos-rebuild --rollback from the console/SSH.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.custom.autoUpdate;
in {
  options.custom.autoUpdate.hour = lib.mkOption {
    type = lib.types.int;
    default = 4;
    description = "Hour of day (UTC) for the daily switch";
  };

  config = {
    systemd.timers."timestone-auto-update" = {
      description = "Daily Timestone NixOS auto-update";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "*-*-* ${toString cfg.hour}:10:00";
        Persistent = true; # catch up after downtime
      };
    };

    systemd.services."timestone-auto-update" = {
      description = "nixos-rebuild switch from the public timestone-tofu flake";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      path = [pkgs.git]; # flake fetch may use git
      serviceConfig = {
        Type = "oneshot";
        # nixos-rebuild does its own activation; give a full nix build room
        TimeoutStartSec = "30min";
      };
      script = ''
        ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch \
          --flake "github:2143-Labs/timestone-tofu?dir=nixos#${config.networking.hostName}"
      '';
    };
  };
}
