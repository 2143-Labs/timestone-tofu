# ts-hz-db — k3s AGENT (CNPG primary + Temporal; nodeSelector pins them here)
{...}: {
  imports = [
    ../modules/auto-update.nix
  ];

  networking.hostName = "ts-hz-db";

  custom.k3s = {
    role = "agent";
    ownIp = "<TS-HZ-DB-IP>"; # FILL from `tofu output nodes` (Stage 2.2)
    peerIp = "<TS-HZ-CTL-IP>"; # FILL from `tofu output nodes` (Stage 2.2)
    officeIp = "<OFFICE-IP>"; # office public IPv4 — SSH only source
    serverAddr = "https://<TS-HZ-CTL-IP>:6443"; # FILL (Stage 2.2)
  };
}
