# ts-hz-ctl — k3s SERVER (control plane + ArgoCD + traefik/cloudflared via waves)
{...}: {
  imports = [
    ../modules/argocd-bootstrap.nix
    ../modules/k8s-secrets-bootstrap.nix
    ../modules/auto-update.nix
  ];

  networking.hostName = "ts-hz-ctl";

  custom.k3s = {
    role = "server";
    ownIp = "46.224.91.55"; # Hetzner nbg1 (tofu output nodes.ctl)
    peerIp = "178.104.247.194"; # ts-hz-db
    officeIp = "108.56.153.222"; # office public IPv4 — SSH/kube API only source
  };
}
