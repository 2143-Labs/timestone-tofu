# ts-hz-db — k3s AGENT (CNPG primary + Temporal; nodeSelector pins them here)
{...}: {
  imports = [
    ../modules/auto-update.nix
  ];

  networking.hostName = "ts-hz-db";

  custom.k3s = {
    role = "agent";
    ownIp = "178.104.247.194"; # Hetzner nbg1 (tofu output nodes.db)
    peerIp = "46.224.91.55"; # ts-hz-ctl
    officeIp = "108.56.153.222"; # office public IPv4 — SSH only source
    serverAddr = "https://46.224.91.55:6443"; # ts-hz-ctl k3s API
  };
}
