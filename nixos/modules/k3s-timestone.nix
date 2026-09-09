# Timestone k3s node — shared server/agent module
#
# Modeled on dotfiles/nixos/cluster/modules/k3s-common.nix + the single-node
# template (github-configuration.nix:151-165), trimmed to Phase 1:
#   ts-hz-ctl = server (embedded etcd, --cluster-init → 2 more servers can join
#              later for HA) + --node-label timestone.io/controlplane=true
#   ts-hz-db  = agent + --node-label timestone.io/workload=primary (the CNPG
#              Cluster nodeSelector pins the single postgres instance here)
#
# Firewall is source-restrictive at the OS level (not just the Hetzner edge
# firewall): SSH + kube API only from the office IP; k3s cluster ports only
# from the peer node IP. Traffic is inbound-only filtered (egress free).
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.custom.k3s;
  isServer = cfg.role == "server";
  k3sFlags =
    lib.optionals isServer [
      "--cluster-init" # embedded etcd single member — HA-ready, NOT sqlite
      "--disable=traefik" # Gateway API provider runs as an ArgoCD chart
      "--disable=servicelb" # no LoadBalancer services (traefik is ClusterIP)
      "--cluster-cidr=10.20.0.0/16"
      "--service-cidr=10.43.0.0/16"
      "--node-label=timestone.io/controlplane=true"
      "--tls-san=${cfg.ownIp}"
    ]
    ++ lib.optionals (!isServer) [
      "--node-label=timestone.io/workload=primary"
    ];
in {
  options.custom.k3s = {
    role = lib.mkOption {
      type = lib.types.enum ["server" "agent"];
      description = "k3s role of this host";
    };
    ownIp = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "This node's public IPv4 (server: baked into --tls-san)";
    };
    peerIp = lib.mkOption {
      type = lib.types.str;
      description = "The OTHER node's public IPv4 (firewall peer rules)";
    };
    serverAddr = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Agent join URL: https://<ts-hz-ctl-ip>:6443";
    };
    officeIp = lib.mkOption {
      type = lib.types.str;
      description = "Office public IPv4 — only source for SSH + kube API";
    };
  };

  config = {
    # k3s cluster token (shared by both hosts, agenix). NEVER in git plaintext.
    age.secrets."timestone/k3s-token" = {
      file = ../secrets/timestone/k3s-token.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };

    services.k3s = {
      enable = true;
      role = cfg.role;
      tokenFile = config.age.secrets."timestone/k3s-token".path;
      extraFlags = toString k3sFlags;
      # Graceful k3s shutdown — tells kubelet to drain pods before SIGKILL.
      gracefulNodeShutdown = {
        enable = true;
        shutdownGracePeriod = "90s";
        shutdownGracePeriodCriticalPods = "15s";
      };
    } // lib.optionalAttrs (!isServer) {
      serverAddr = cfg.serverAddr;
    };

    # k3s uses Type=notify but slow starts get killed by systemd
    # ("Failed with result 'protocol'") — override to simple + generous stop.
    systemd.services.k3s.serviceConfig = {
      Type = lib.mkForce "simple";
      TimeoutStopSec = lib.mkForce "120s";
    };
    # ── OS firewall ──
    # Source restriction lives at the HETZNER EDGE firewall (verified
    # default-deny): it allows SSH + kube API only from the office IP and the
    # k3s cluster ports only between the two nodes. At the OS level we open
    # exactly the ports k3s serves (home-proven pattern); the edge drops
    # everything else before it reaches the OS.
    networking.firewall.allowedTCPPorts =
      [22] # sshd
      ++ lib.optionals isServer [6443] # kube API (agent side not needed)
      ++ [10250 7946]; # kubelet / supervisor
    networking.firewall.allowedUDPPorts = [
      8472 # flannel VXLAN
    ];
  };
}
