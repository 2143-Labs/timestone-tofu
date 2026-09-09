# Shared SSH authorized keys for root + agenix identities
#
# Adapted from dotfiles/nixos/cluster/modules/ssh.nix. Keys are hardcoded here
# (public material — fine in a public repo) instead of passed via specialArgs:
# office login key, office age key, arch fallback.
{...}: {
  users.users.root.openssh.authorizedKeys.keys = [
    # office SSH login key (id_ed25519.pub)
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFVckq0oXyXkxiLo39typ6PR039XrLwze/Cb0PZaTzmi john@office"
    # office age identity (age.pub) — agenix recipient/decrypt from office
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHvBxDHUfnnQSNGr3K35hacUDFzveraQ3F0JKcwUDHr5 john@office"
    # arch machine fallback
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOktI2Vry/5fbhZiG35o5mf7w3dnaTEDqkRJVM07cu3a john@arch"
  ];
  services.openssh.enable = true;

  # agenix identity — /etc/ssh/age-identity is the shared node key pushed at
  # install (nixos-anywhere --extra-files); the host key is a second identity.
  age.identityPaths = ["/etc/ssh/age-identity" "/etc/ssh/ssh_host_ed25519_key"];
}
