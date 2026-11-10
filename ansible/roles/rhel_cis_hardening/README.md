# rhel_cis_hardening

Hardens a RHEL-family host (developed against Rocky Linux 9) in areas the CIS Benchmark covers. It does **not** claim compliance with the benchmark.

## What it configures

| Area | File written | Notes |
|---|---|---|
| SSH | `/etc/ssh/sshd_config.d/00-hardening.conf` | Named `00-` on purpose: sshd keeps the **first** value it reads, and the vendor `50-redhat.conf` would otherwise win. Algorithms are left to the system-wide crypto-policy. |
| Kernel / network | `/etc/sysctl.d/60-hardening.conf` | Redirects, source routing, rp_filter, syncookies, ASLR, `kptr_restrict`, `dmesg_restrict`, core dump limits. `ip_forward` is off unless you set `rhel_cis_hardening_ip_forward: true` (needed on routers and Docker hosts). |
| Kernel modules | `/etc/modprobe.d/60-hardening.conf` | cramfs, freevxfs, jffs2, hfs, hfsplus, udf, usb-storage. |
| Passwords | `pwquality.conf.d/60-hardening.conf`, `/etc/login.defs` | length 14, 4 classes, aging, umask 027. |
| Audit | `/etc/audit/rules.d/60-hardening.rules` | identity files, sudoers, sshd/SELinux config, logins and sessions. |
| Firewall | `/etc/nftables/hardening.nft` | default drop inbound; established, loopback, ICMP and the listed TCP ports are allowed. Validated with `nft -c` before it is written. |
| Permissions | `/etc/passwd`, `shadow`, `group`, `gshadow`, `sshd_config` | |
| Banner | `/etc/issue`, `/etc/issue.net` | |
| SELinux, services | (real hosts only) | enforcing + targeted; enables auditd and nftables; disables avahi, cups, rpcbind, telnet, vsftpd if present. |

All variables are in `defaults/main.yml`, prefixed `rhel_cis_hardening_`.

## Read this before running it on a real host

- **Firewall lockout.** The ruleset drops inbound traffic except `rhel_cis_hardening_nft_allowed_tcp_ports` (default `[22]`). If SSH listens elsewhere, change the list first, and test from a console. On hosts that route or run containers set `rhel_cis_hardening_nft_forward_policy: accept`.
- **SSH is key-only by default** (`PasswordAuthentication no`). Deploy a key first, or set `rhel_cis_hardening_ssh_password_authentication: "yes"` until you have one.
- **SELinux** changed from `disabled` to `enforcing` needs a reboot and a filesystem relabel. The role reports that a reboot is required; it never reboots.
- Run with `--check --diff` first.

## What is tested

In CI, against a `rockylinux:9` container (`.github/workflows/pipeline.yml`, job `role-test`):

1. the role is applied;
2. it is applied a **second time and must report `changed=0`** (idempotence);
3. `tests/verify.yml` checks the result: `sshd -T` (the *effective* sshd configuration, vendor drop-ins included), `nft -c` on the ruleset, the hardened lines in each managed file, and file permissions.

`ansible-lint` also runs with the strictest (`production`) profile.

**Not tested**, because a container has no systemd, a read-only `/proc/sys` and no SELinux: that services are enabled or stopped, that sysctl values are applied to a running kernel, that SELinux is enforcing, and that the firewall loads and still lets you in. Those tasks are skipped there (`rhel_cis_hardening_manage_services: false`) and need a VM to verify.
