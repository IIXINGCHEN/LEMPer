# LEMPer Security Notes

Hardening features shipped with LEMPer, and what is deliberately left to the
server administrator.

---

## 1. AppArmor: NOT auto-enforced (by design)

LEMPer does **not** install, generate, or enforce custom AppArmor profiles for
nginx, php-fpm, mariadb, or any other component.

Rationale:

- **Ubuntu enables AppArmor by default** and ships its own maintained
  profiles (e.g. for `mysqld`). LEMPer does not disable AppArmor; the
  distro profiles keep working as usual.
- **Package updates break static profiles.** nginx, PHP, and MariaDB updates
  regularly change binary paths, configuration locations, log/socket paths,
  and required capabilities. A LEMPer-shipped static profile would go stale
  and deny legitimate access after an update — e.g. php-fpm failing to
  start — producing outages that are hard to diagnose.
- **Least-privilege profiles need per-deployment tuning.** Web roots, pool
  sockets, custom config locations, and enabled modules differ per server,
  so an installer cannot know the correct ruleset in advance.

If you want custom enforcement, do it yourself on the target server:

1. Generate a profile from real traffic: `aa-genprof /usr/sbin/nginx`
2. Run in **complain mode** first and review denials with `aa-logprof`.
3. Re-test after every nginx/PHP/MariaDB upgrade, because paths and
   capabilities change.

Enforcing custom profiles is a conscious administrator decision, not an
installer default.

---

## 2. Jailkit SFTP chroot (optional, default OFF)

`scripts/install_jailkit.sh` (env: `INSTALL_JAILKIT=false` in `.env.dist`)
installs the `jailkit` package from the distro repository, initializes a
base chroot jail skeleton at `/home/jail` via `jk_init` (using the `sftp`
profile from `/etc/jailkit/jk_init.ini` when available), registers `jk_lsh`
in `/etc/shells`, and installs the helper `/usr/local/bin/lemper-jail-user`.

Jailing an existing user:

```bash
adduser --disabled-password --gecos "" sftpuser   # if the user is new
sudo lemper-jail-user sftpuser                    # chroot + restrict shell
```

The helper is idempotent: re-running it on an already-jailed user only
confirms the state. Remove everything with `scripts/remove_jailkit.sh`
(it asks before deleting the jail directory, which holds jailed users' data).

For SFTP-only access, add an sshd `Match` block (see the script header in
`scripts/install_jailkit.sh`) and reload sshd.

Caveats:

- The jail is a **chroot**, not a container: it limits filesystem visibility,
  it does not isolate CPU/memory/network (use the cgroup limits below and/or
  the firewall for that).
- Jailed users share one jail root (`/home/jail`); do not put sensitive
  host files inside it.
- `jk_lsh` only permits the commands whitelisted in the jail's
  `etc/jk_lsh.ini`; adjust it if jailed users need more than SFTP.

---

## 3. systemd cgroup resource limits for PHP-FPM (optional, default OFF)

`scripts/apply_fpm_limits.sh` is a sourced snippet (called from `install.sh`
after the PHP installation). For each installed `phpX.Y-fpm.service` it
writes a systemd drop-in:

`/etc/systemd/system/phpX.Y-fpm.service.d/limits.conf`

```ini
[Service]
CPUQuota=50%
MemoryMax=512M
```

controlled by `.env` variables (both default to empty = disabled):

```ini
PHP_FPM_CPU_QUOTA=""
PHP_FPM_MEMORY_MAX=""
```

Behavior notes:

- **Safe no-op when empty:** if both variables are empty, no drop-in files
  are written and no `daemon-reload` is triggered.
- Only directives with non-empty values are written; e.g. setting only
  `PHP_FPM_MEMORY_MAX` produces a drop-in with just `MemoryMax=`.
- Versions are taken from `PHP_VERSIONS`; a drop-in is written only when
  the corresponding `phpX.Y-fpm.service` unit file exists.
- `daemon-reload` runs after writing, but **limits take effect on the next
  service restart** (`systemctl restart php8.4-fpm`). Running workers keep
  their old limits until restarted.
- `CPUQuota=` accepts percentages (`50%`, `200%` for 2 CPUs);
  `MemoryMax=` accepts bytes with K/M/G suffixes (`512M`, `2G`).
  Invalid values make the unit fail to start — validate with
  `systemd-analyze verify php8.4-fpm.service` after changing them.
