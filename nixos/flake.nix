# Timestone NixOS — Phase 1 Hetzner hosts (ts-hz-ctl server / ts-hz-db agent)
#
# Sub-flake under timestone-tofu/nixos (reference it from the repo root as
# `github:2143-Labs/timestone-tofu?dir=nixos#ts-hz-ctl` — used by the nodes'
# daily auto-update). Mirrors the dotfiles cluster flake, trimmed to two hosts.
{
  description = "Timestone k3s nodes — Hetzner (ts-hz-ctl server, ts-hz-db agent)";

  inputs = {
    # Pinned at the rev locked in dotfiles/nixos/cluster/flake.lock at plan time.
    nixpkgs.url = "github:NixOS/nixpkgs/549bd84d6279f9852cae6225e372cc67fb91a4c1";

    disko = {
      url = "github:nix-community/disko/63b4e7e6cf75307c1d26ac3762b886b5b0247267";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix/b027ee29d959fda4b60b57566d64c98a202e0feb";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    disko,
    agenix,
    ...
  }: let
    system = "x86_64-linux";
    mkHost = hostName: nixpkgs.lib.nixosSystem {
      inherit system;
      # Hetzner defaults (disko.nix module args)
      specialArgs = {
        diskDevice = "/dev/sda";
        useEFI = true;
      };
      modules = [
        disko.nixosModules.default
        agenix.nixosModules.default
        ./modules/disko.nix
        ./modules/ssh.nix
        ./modules/k3s-timestone.nix
        ./hosts/${hostName}.nix
      ];
    };
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    nixosConfigurations = {
      ts-hz-ctl = mkHost "ts-hz-ctl"; # k3s server + ArgoCD + secrets oneshots
      ts-hz-db = mkHost "ts-hz-db"; # k3s agent — CNPG primary/Temporal workloads
    };

    devShells.${system}.default = pkgs.mkShell {
      packages = with pkgs; [
        nixos-anywhere # OS install/bootstrap
        age # encrypt secrets/*.age for the nodes
        openssl # `openssl rand -base64 32` for the k3s token
      ];
    };
  };
}
