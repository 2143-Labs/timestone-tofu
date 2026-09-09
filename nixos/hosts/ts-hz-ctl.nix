# ts-hz-ctl — k3s SERVER (control plane + ArgoCD + cloudflared/traefik/cnpg via waves)
{...}: {
  imports = [
    ../modules/argocd-bootstrap.nix
    ../modules/k8s-secrets-bootstrap.nix
    ../modules/auto-update.nix
  ];

  networking.hostName = "ts-hz-ctl";

  custom.k3s = {
    role = "server";
    ownIp = "<TS-HZ-CTL-IP>"; # FILL from `tofu output nodes` (Stage 2.2)
    peerIp = "<TS-HZ-DB-IP>"; # FILL from `tofu output nodes` (Stage 2.2)
    officeIp = "<OFFICE-IP>"; # office public IPv4 — SSH/kube API only source
  };
}
