# fail2ban — exponential-backoff brute-force protection on the sshd jail.
#
# Lives in core (not loaded) so #base images aren't deployed without it.
{
  services.fail2ban = {
    enable = true;
    maxretry = 3;
    bantime = "24h";
    bantime-increment = {
      enable = true;
      maxtime = "168h";
      factor = "4";
    };
    jails.sshd.settings = {
      enabled = true;
      port = "ssh";
      findtime = 300;
    };
  };
}
