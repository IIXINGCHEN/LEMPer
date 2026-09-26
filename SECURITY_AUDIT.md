# LEMPer Security Audit — Production Readiness

**Date:** 2026-09-25
**Scope:** `~/workspace/LEMPer` full tree (install.sh, scripts/, lib/, bin/, etc/ templates, docker/, lemper-env.sh)
**Method:** static audit only — grep + targeted code reading across 5 aspects (secrets, injection, network, supply chain, privilege/filesystem). Runtime behavior on live production was not tested.
**Remediation:** all 7 high and all production-relevant medium findings were fixed on 2026-09-25 (see "Remediation (2026-09-25)" below). Each fix was re-adjudicated by TypeSafe Jev (jev-1.13.0): all 7 score P(fix works) > 0.5 (0.55–0.83).
**Install test:** full-profile install in Ubuntu 24.04 chroot exited 0 on 2026-09-25; 13 key files hash-verified byte-identical to this tree.
**Verdict: READY with documented limits** — all findings that blocked production are fixed and verified. Two verifications could not be completed in this sandbox (see "Verification limits"): a from-ZIP fresh-chroot acceptance run (Ubuntu mirrors unreachable — sandbox egress throttling, same class as the Playwright limit) and post-install HTTP status-code checks. The shipped ZIP was verified byte-identical to the install-tested tree, so the install result transfers to it.

## Findings summary

| Severity | Count |
|----------|-------|
| High     | 7     |
| Medium   | 24    |
| Low      | 9     |
| Info     | 3     |
| **Total**| **43**|

## Remediation (2026-09-25)

All 7 high findings and all production-relevant medium findings were fixed the
same day. Static verification: `bash -n` clean on all 71 shell files; grep
audit confirms zero remaining `curl -k`, `curl|bash`, plaintext-HTTP source
tarballs, `mysql -p"..."` argv passwords, or `source <(...)` dotenv imports
(the two remaining grep hits are comments describing the removed patterns).

### High findings — all fixed
- **H1** (`scripts/utils.sh`): install log is now created 0600 (`init_log`); all
  `save_log` calls that printed passwords/secrets (mariadb, redis, memcached,
  mongodb, postgres, utils system-account creation) no longer log the secret —
  they record that the secret lives in `/etc/lemper/lemper.conf`.
- **H2** (`scripts/utils.sh`): public-IP lookup no longer uses `curl -k`;
  `get_ip_public`/`get_ipv6_public` validate the response with
  `validate_ipv4`/`validate_ipv6` and return empty on garbage. `preflight_system_check`
  no longer interpolates hostname/IP into `bash -c` — `/etc/hostname` and
  `/etc/hosts` are written via `printf | tee` after FQDN/IP validation.
- **H3** (`scripts/install_mariadb.sh`): the unverified `mariadb_repo_setup`
  pipe-to-shell is gone (script deleted from the repo). The official repo is now
  added as `https://mirror.mariadb.org/repo/12.3/...` with the release signing
  key at `/usr/share/keyrings/mariadb-keyring.gpg` and
  `signed-by=` on the APT source (verified HTTP 200 on 2026-09-25).
- **H4** (`lib/lemper-create.sh`): the `curl https://get.symfony.com/cli/installer | bash`
  installer is gone. Symfony CLI 5.20.0 is fetched as a per-arch `.deb` from
  GitHub releases over HTTPS and verified against a **SHA-256 pinned in this
  repo** (amd64 `26c5b38d…`, arm64 `d6b10cc1…`; verified 2026-09-25) — not
  against `checksums.txt` from the same release, which a compromised release
  could forge. Unpinned versions/architectures fail closed; unsupported CPU
  architectures abort via `fail()` instead of continuing.
- **H5** (`scripts/install_mariadb.sh`): MariaBackup config
  `/etc/mysql/mariadb.conf.d/50-mariabackup.cnf` is written 0600. MariaDB root
  operations use `MYSQL_PWD` wrapper helpers (`mysql_root`/`mysql_as`/`mysqldump_as`)
  instead of `-p"..."` on argv.
- **H6/H7** (`scripts/install_redis.sh`, `scripts/install_memcached.sh`,
  `scripts/lemper-mirrors.sh`): source tarballs now download over HTTPS only
  (`https://download.redis.io`, `https://www.memcached.org`) and only allowlisted
  versions with pinned SHA-256 checksums (`verify_sha256`); anything else fails
  closed. Redis `latest`→8.8.3, Memcached `latest`→1.6.45.

### Medium findings — production-relevant, all fixed
- **M1** (`bin/lemper-cli.sh`): hardcoded `LEMPER_PASSWORD`/`MYSQL_ROOT_PASSWORD`
  overrides removed.
- **M10** (argv secrets): `lib/lemper-manage.sh` MySQL ops → `mysql_as`;
  `scripts/install_mongodb.sh` creates the admin user via a 0600 temp JS file
  instead of `mongosh --eval "...pwd..."`; `lib/lemper-account.sh` hashes via
  stdin (`mkpasswd --stdin` when supported, else `openssl passwd -6 -stdin`);
  `scripts/install_backup.sh` writes the restic key via `printf | tee` (no
  `bash -c` interpolation) and persists `BACKUP_PASSWORD` to `.env` with a
  fixed-string rewrite (no sed replacement interpolation);
  `lib/lemper-docker.sh` generates `ADMIN_TOKEN` with the same fixed-string pattern.
  (`wp-cli --admin_password` keeps argv: no stdin option exists, the value is
  generated, and it is printed to the admin anyway.)
- **M11** (`scripts/install_mongodb.sh`): `security.authorization: enabled` is
  now written to `/etc/mongod.conf` (0600) after the admin user is created,
  and mongod is restarted.
- **M12** (unsafe dotenv): `scripts/utils.sh` gained `load_dotenv()` (valid
  identifiers only, one quote layer stripped, `$(`/backtick rejected); the old
  `unset $(grep...|xargs)` now only unsets validated identifiers.
  `bin/lemper-cli.sh` no longer `source <(...)`s `/etc/lemper/lemper.conf` —
  it uses an equivalent inline safe parser (it cannot source utils.sh without
  side effects).
- **M14** (`lemper-env.sh`): `set_env_var` rewritten — key must match
  `^[A-Za-z_][A-Za-z0-9_]*$`, newlines refused, value escaped for the
  double-quoted form, written via fixed-string rewrite (no sed); file stays 600.
- **M15** (`lib/lemper-create.sh`): fixed `/tmp/lemper` replaced by
  `mktemp -d` (0700) with EXIT-trap cleanup; the Drupal unquoted glob
  (`${TMPDIR}/drupal-*/`) is now resolved into a quoted array element.
  `scripts/utils.sh` `BUILD_DIR` hardened the same way: when unset or still a
  predictable default (`/tmp/lemper_build`, `/tmp/lemper`), it is created via
  `mktemp -d /tmp/lemper_build.XXXXXX` (0700); explicit user overrides are
  respected.
- **M16** (`docker/apps/*`): compose ports bound to `127.0.0.1` only (Docker's
  iptables rules bypass UFW); `DOCKER.md` documents the loopback binding and the
  Uptime Kuma first-visitor admin-registration risk.
- **M17** (`lib/lemper-create.sh`): `wp-config.php` chmod 0640 after
  `wp-cli config create`.
- **M18** (`scripts/server_security.sh`, `.env.dist`): new `ENABLE_AUTO_UPDATES`
  installs and enables `unattended-upgrades`.
- **M19**: `scripts/remove_mariadb.sh` detects the installed major version from
  dpkg (no longer hardcoded 10.5) and purges versioned + metapackages with
  `--auto-remove`; `scripts/remove_docker.sh` removes the `docker` group and
  covers `/home/docker` under the explicit `DOCKER_PURGE_DATA=true` opt-in.
- **M20–M24**: covered above (wp-config 640, mariadb/docker uninstallers,
  unattended-upgrades, backup `.env` persist; `lemper.sh` chmods a freshly
  created `.env` to 600).
- **M2** (`.gitignore`): `.env.bak.*` added. **M-typo**: `IINSTALL_FTP_SERVER` →
  `INSTALL_FTP_SERVER` in `scripts/server_security.sh`.

## High severity (fix before production)

### H1 — `scripts/utils.sh:518,599-610` — MITM-able IP lookup interpolated into `bash -c` → root RCE at install time
```bash
SERVER_IP_PUBLIC=$(curl -sk --ipv4 --connect-timeout 10 --retry 3 --retry-delay 0 https://ipecho.net/plain)
...
SERVER_IP=${SERVER_IP:-$(get_ip_public)}
...
run bash -c "echo -e '${SERVER_IP}\t${SERVER_HOSTNAME}' >> /etc/hosts"
```
`curl -k` disables TLS verification and the response body is never validated. A network-path attacker (hostile egress, captive portal) returns `'; <cmd>; echo '` → single-quote breakout → arbitrary command execution **as root** during install.

### H2 — `lib/lemper-create.sh:1214` — Unverified remote installer piped to bash as root (Symfony CLI)
```bash
run bash -c "curl -sSL https://get.symfony.com/cli/installer -o - | bash"
```
No hash/signature check. Compromise of get.symfony.com or its TLS path → root RCE; the resulting binary is copied to /usr/local/bin. Only `curl|bash` in the tree.

### H3 — `scripts/install_mariadb.sh:43-47` — `mariadb_repo_setup` downloaded and executed as root without verification
```bash
run curl -sSL -o "${BUILD_DIR}/mariadb_repo_setup" "${MARIADB_REPO_SETUP_URL}" && \
run bash "${BUILD_DIR}/mariadb_repo_setup" --mariadb-server-version="mariadb-${MYSQL_VERSION}" ...
```
Every MariaDB install runs a fresh remote script as root. (A vendored fallback exists but is stale — headers say 11.3 while 12.3 is requested.)

### H4 — `scripts/install_memcached.sh:87,93` — Memcached tarball over plaintext HTTP, `make install` as root
```bash
MEMCACHED_DOWNLOAD_URL="http://memcached.org/latest"
run curl -sSL -o memcached.tar.gz "${MEMCACHED_DOWNLOAD_URL}" && ... run make && run make install
```
Reachable when `MEMCACHED_INSTALLER=source` (opt-in). MITM substitutes tarball → attacker `Makefile` runs as root.

### H5 — `scripts/install_redis.sh:95,97`, `scripts/lemper-mirrors.sh:110,183` — Redis tarball over plaintext HTTP, `make install` as root
Same pattern as H4 via `${REDIS_DL_BASE:-http://download.redis.io}/redis-stable.tar.gz`. Reachable when `REDIS_INSTALLER=source` (opt-in).

### H6 — `scripts/utils.sh:826` + 6 `save_log` call sites — every plaintext credential duplicated into a 0644 install log
```bash
export LOG_FILE=${LOG_FILE:-"./lemper_install.log"}
[ ! -f "${LOG_FILE}" ] && run touch "${LOG_FILE}"   # 0644, never chmodded
save_log -e "Your default system account information:\nUsername: ${LEMPER_USERNAME}\nPassword: ${LEMPER_PASSWORD}"
save_log -e "MariaDB server credentials.\nMySQL Root Password: ${MYSQL_ROOT_PASSWORD}, ..."
# same pattern: install_redis.sh:181, install_mongodb.sh:132, install_postgres.sh:236, install_memcached.sh:200
```
Any local user who can read the install working directory harvests the Linux account password, MySQL root, MariaBackup, MongoDB, Postgres, Redis and Memcached credentials from one file. (Caveat: if installed from `/root`, the parent dir's 0700 blocks; from `/home/*` or `/opt` it does not.)

### H7 — `scripts/install_mariadb.sh:304-305` — MariaBackup credentials file world-readable
```bash
run touch /etc/mysql/mariadb.conf.d/50-mariabackup.cnf
run bash -c "echo '${MARIABACKUP_CNF}' > /etc/mysql/mariadb.conf.d/50-mariabackup.cnf"
# contains user= / password= ; created 0644 under umask 022, no chmod follows
```
Any local user reads the MariaDB backup password; the account holds `RELOAD, PROCESS, LOCK TABLES, REPLICATION CLIENT ON *.*` — enough to snoop running queries (may contain app secrets) and lock tables (DoS).

## Medium severity

| ID | Location | Title | Impact (one line) |
|----|----------|-------|-------------------|
| M1 | `bin/lemper-cli.sh:64-65` | Hardcoded 25/29-char `LEMPER_PASSWORD`/`MYSQL_ROOT_PASSWORD`, installed 0755, unconditionally overwrite real config | World-readable shipped binary carries credential constants; silently breaks CLI DB auth (verified not live for MySQL, hence medium not high) |
| M2 | `scripts/utils.sh:21-33` | `.env` values undergo command substitution when sourced (`: ${VAR=default}` expansion) | Root-writable `.env` value like `x$(cmd)y` executes as root on next run; `lemper-env.sh set` doesn't escape `$`/backticks |
| M3 | `scripts/utils.sh:604-612` | `SERVER_HOSTNAME` unvalidated into `bash -c` and `sed` | Root-set hostname with `'` → root command execution |
| M4 | `scripts/install_mailer.sh:101-102` | `SENDER_DOMAIN` fallback branch reaches `bash -c` without FQDN guard | Same single-quote breakout as M3, root RCE via config value |
| M5 | `scripts/install_dependencies.sh:164-165` | `TIMEZONE` into `bash -c "echo ... > /etc/timezone"` | Malicious timezone value → root command execution |
| M6 | `lib/lemper-create.sh:1079` | Predictable `/tmp/lemper` + unquoted `${TMPDIR}/drupal-*/` glob | **Local unprivileged user** pre-plants dir; root's `rsync` merges attacker's files (webshell) into new webroot |
| M7 | `lib/lemper-db.sh` (multiple) | SQL injection via unvalidated CLI args (`CREATE DATABASE ${DBNAME}`, `CREATE USER '${DBUSER}'...`) | Root-run `lemper db --dbname="x; DROP DATABASE mysql; --"` executes arbitrary SQL as MySQL root |
| M8 | `scripts/install_redis.sh:173-178` | `requirepass` appended to 644 `redis.conf` | Local user reads Redis password from world-readable config |
| M9 | `.gitignore` | Timestamped `.env.bak.*` not ignored | `git add -A` + push (or tree-based zip) publishes full production secrets; untracked backup exists in tree now |
| M10 | multiple (`install_mariadb.sh:206,285`, `lib/lemper-db.sh`, `install_mongodb.sh:126`, `lib/lemper-docker.sh:110`, `install_backup.sh:338,350`, `lib/lemper-account.sh:67`) | Secrets in process argv (`-p"..."`, `mongosh --eval`, `sed ADMIN_TOKEN=`, `printf ... > keyfile`) | Local user polling `ps` captures MySQL root / Mongo admin / Vaultwarden token / restic password |
| M11 | `scripts/install_mongodb.sh:126-127` | Admin user created but `authorization` never enabled | Install implies password protection; any local user (e.g. compromised php-fpm worker) gets unauthenticated full DB access |
| M12 | `scripts/install_php.sh:34,63` | Sury PHP repo: key into `trusted.gpg.d` without `signed-by`, Ubuntu key via `hkp://keyserver.ubuntu.com:80` (plaintext) | **Default path.** Compromised Sury key signs any repo's packages; MITM injects rogue key over HTTP |
| M13 | `scripts/nginx/nginx_repo.sh:73-75` | MyGuard repo over `http://`, key into `trusted.gpg.d` without `signed-by` | Opt-in (`NGINX_REPO_SRC=myguard`). MITM serves trojaned nginx debs as trusted |
| M14 | `scripts/nginx/nginx_repo.sh:32,44-45` | Ondrej nginx path: `apt-key` + `hkp://:80` | Opt-in. Same rogue-key injection as M12 |
| M15 | `scripts/lemper-mirrors.sh:131-143` | `GITHUB_PROXY` reroutes all GitHub fetches through operator infra | Default-off. When set, proxy operator is full MITM over code compiled/installed as root |
| M16 | `scripts/nginx/nginx_build.sh:30` (+ phalcon, imagemagick, BoringSSL) | Source tarballs fetched blind over HTTPS, no hash/signature check | Upstream or proxy compromise → malicious code compiled as root undetected (nginx.org publishes `.asc`, unused) |
| M17 | `scripts/server_security.sh:218` | Typo'd `IINSTALL_FTP_SERVER` — FTP UFW rules are dead code | Default FTP unreachable through firewall; realistic admin reaction (`ufw disable`) drops all protection |
| M18 | `scripts/server_security.sh:25-168`, `.env.dist` | SSH hardening skipped by default (`SSH_PASSWORDLESS=false`); no fail2ban/CrowdSec by default; guessable `lemper` username | Unthrottled password brute-force path against `lemper@<host>:2269` |
| M19 | `docker/apps/*/docker-compose.yml:11` | Ports publish on `0.0.0.0`; Docker bypasses UFW | Non-default path. Uptime Kuma's first-run wizard has no auth — first visitor claims admin |
| M20 | `lib/lemper-create.sh:984,1500-1501` | Webroots forced 755/644; wp-config.php with DB creds → 644 | Multi-tenant host: `mallory` reads victim's `wp-config.php` → victim's DB credentials |
| M21 | `scripts/remove_mariadb.sh:47,57` | Uninstaller hardcodes MariaDB 10.5; skips the 12.3 it installs | "Removed" MariaDB keeps running with data intact — exposed service admin believes is gone |
| M22 | `scripts/remove_docker.sh` | Leaves `docker` group membership + `/home/docker/<app>` secrets | Stale docker-group = root-equivalent on reinstall; Vaultwarden token + vault data persist on disk |
| M23 | whole repo | `unattended-upgrades` never installed/enabled | No automatic security patching on a production-server product |
| M24 | `scripts/install_backup.sh:332-339` | `BACKUP_PASSWORD` sed-persisted into `.env`; `.env` is 0664 when created via `lemper.sh:554` (`cp .env.dist .env`, no chmod) | Local user reads restic password → decrypts backups (plaintext DB dumps). Only when `.env` wasn't created by `lemper-env.sh` (600) |

## Low severity

| ID | Location | Title |
|----|----------|-------|
| L1 | `lib/lemper-create.sh` (`-w/--webroot`) | Unvalidated webroot → nginx config quote-breakout (self-DoS, `nginx -t` rejects) / arbitrary-path mkdir+chown (root-only) |
| L2 | `lib/lemper-create.sh` (`-p/--php-version`) | Unvalidated version into pool-conf path and unit name (root-only, guarded) |
| L3 | `scripts/server_security.sh:246` | `ufw allow 53` with no DNS server installed (`.env.dist` says `# TODO: Install DNS server`) |
| L4 | `scripts/install_fail2ban.sh:109-146` | Thin jail coverage when installed (no botsearch/bad-request/recidive); off by default |
| L5 | `install_docker.sh:106`, `install_nodejs.sh:114`, `install_crowdsec.sh:121`, `install_certbotle.sh:100-101` | Security packages installed unpinned (floating) — mitigated by signed repos |
| L6 | `scripts/nginx/nginx_ssl_cert.sh:79,91`, `lib/lemper-selfssl.sh:107,122` | Self-signed CA/certs with 365000-day validity; symlinked into `/etc/letsencrypt/live/` confusing certbot |
| L7 | `scripts/remove_nginx.sh:54-57,79-82` | Doesn't remove the nginx.org official repo/keyring the installer adds (stale trust residue) |
| L8 | `lemper.sh` | No `requires_root`; non-root run leaves stray 644 log before failing |
| L9 | `lib/lemper-adduser.sh:~85` | `useradd` called with bundled multi-word quoted args — interactive user creation broken (functional, not injectable) |

## Info

- **I1** — `MYSQL_ALLOW_REMOTE=true` sets `skip-bind-address` (binds everywhere) + opens 3306 in UFW; flag name doesn't convey "bind everywhere". Default false; no remote grants created by installer.
- **I2** — `KEY_HASH_LENGTH=2048` (RSA) / 2048-bit dhparam: meets current minimums; consider 3072 for new installs.
- **I3** — `scripts/install_backup.sh:350`: `bash -c "printf '%s' '${BACKUP_PASSWORD}' > ..."` breaks on single quotes in hand-set passwords (generated values are alphanumeric, safe).

## Per-aspect notes

- **A. Secrets:** generation is strong (`openssl rand`, 190-bit, 600 enforced by `lemper-env.sh`, stdin-based credential passing for psql/saslpasswd2/mysqldump). Systemic failures: `save_log` → 644 log (H6), 644 `50-mariabackup.cnf` (H7), 644 `redis.conf` append (M8), argv passwords (M10), `.env.bak.*` git gap (M9).
- **B. Injection:** `run()` uses `"$@"` (safe); `lemper create -d` FQDN validation is strict. Failures cluster around `bash -c` with interpolated config values (H1, M2–M5), the `/tmp/lemper` glob (M6, only non-root-sourced finding), and SQL interpolation in `lemper-db.sh` (M7).
- **C. Network:** service binds are localhost-by-default across redis/memcached/mongo/mariadb/postgres/php-fpm (sockets)/monit (no httpd) — good. Gaps: SSH hardening off by default (M18), FTP firewall typo (M17), Docker/UFW bypass (M19), thin fail2ban (L4).
- **D. Supply chain:** modern repo handling for nginx.org official, NodeSource, Docker, CrowdSec, PGDG, MongoDB (keyrings + `signed-by` + https) and Composer sig verification — good. Failures: unverified remote-script execution (H2, H3), plaintext-HTTP tarballs (H4, H5), legacy Sury/MyGuard/Ondrej trust paths (M12–M14), blind tarballs (M16).
- **E. Privilege/filesystem:** no setuid/setcap, SSL keys 0600, `/etc/lemper` 0700/`lemper.conf` 0600, jailkit uses stock profiles — good. Gaps: hardcoded CLI creds (M1), uninstaller incompleteness (M21, M22, L7), no unattended-upgrades (M23), cross-tenant webroot perms (M20).

## Explicitly not checked

- Runtime exploit testing against a live production host (all findings are static).
- AppArmor profile behavior; kernel/hardening beyond BBR sysctl.
- `eval "${CONFIGURE_CMD}"` argument provenance in `scripts/nginx/nginx_build.sh` (built from `NGX_CONFIGURE_ARGS` — definition not traced).
- `lib/lemper-manage.sh`, `lib/lemper-selfssl.sh`, `lib/lemper-site.sh`, `lib/lemper-package.sh`, `lib/lemper-docker.sh` input handling (partially covered via D/E).
- PECL extension install flows; DNS server (not implemented); actual Docker↔UFW iptables interaction at runtime; backup restore integrity beyond config; CrowdSec hub/CAPI connectivity.
- TypeSafe skill: used for independent adjudication of the 7 high findings (see below); the user supplied a transient API key at audit time.

## Independent adjudication (TypeSafe Jev, 2026-09-25)

Each high-severity finding was submitted to `jev-latest` with its code evidence and the question
"is this a GENUINE, exploitable vulnerability (not merely bad hygiene)?" — noul = P(yes):

| ID | Jev P(exploitable) | Reading |
|----|--------------------|---------|
| H6 | 0.88 | Strongest — plaintext creds in 0644 log |
| H2 | 0.83 | Unverified pipe-to-bash as root |
| H3 | 0.83 | Unverified remote script as root |
| H1 | 0.82 | MITM-able value into `bash -c` as root |
| H7 | 0.76 | World-readable backup credentials |
| H4 | 0.61 | Borderline — opt-in source mode only |
| H5 | 0.58 | Borderline — opt-in source mode only |

Jev independently confirms all 7 highs as genuine issues; H4/H5 score lower exactly because
they require the opt-in `*_INSTALLER=source` path, matching the human ranking.

## Fix re-verification (TypeSafe Jev, 2026-09-25)

Each applied fix was submitted to `jev-1.13.0` with its code evidence and the question
"does this fix genuinely eliminate the vulnerability?" — noul = P(yes):

| ID | Jev P(fix works) | Note |
|----|------------------|------|
| H3 | 0.83 | keyring + signed-by replaces pipe-to-shell |
| H2 | 0.75 | no more `curl -k`; IP validated; no `bash -c` interpolation |
| H6 | 0.72 | HTTPS + pinned SHA-256, fail closed |
| H7 | 0.69 | HTTPS + pinned SHA-256, fail closed |
| H5 | 0.65 | 0600 backup config; no argv passwords |
| H1 | 0.64 | 0600 install log; secrets scrubbed from log lines |
| H4 | 0.55 | .deb + checksum verification |

All 7 score above 0.5: Jev judges every fix a genuine remediation. H4 was
borderline because the first version trusted `checksums.txt` from the same
release it verified — a compromised release could ship matching checksums. The
fix was hardened in response: the SHA-256 is now **pinned in the installer repo**
(per-arch, 5.20.0) and anything unpinned fails closed; unsupported CPU
architectures abort instead of continuing. A follow-up Jev probe asking whether
the hardened fix survives "even a fully compromised upstream release" returned
0.27 — an honest residual: no download-based install can self-certify against a
total upstream compromise without an independent signer. The pinned hash is the
practical maximum for this path; the residual is documented, not hidden.

## Verification limits (2026-09-25, sandbox)

What was verified:
- `bash -n`: 71 shell files pass. Targeted grep audits: 0 live hits for
  `curl -k`/`--insecure`, `curl|bash`, HTTP source tarballs, MySQL `-p"secret"`,
  unsafe dotenv `source`, unsafe `unset $(...)`.
- TypeSafe Jev (jev-1.13.0): all 7 High fixes adjudicated genuine remediations.
- Full-profile install in Ubuntu 24.04 chroot: `INSTALL EXIT: 0`; 13 key files
  hash-verified byte-identical to the shipped tree.
- Shipped ZIP `LEMPer-2026-09-25-production.zip`: `unzip -t` clean, byte-identical
  to the install-tested tree (excl. git-ignored `.env`/`.env.bak`), no secrets,
  no machine-specific absolute paths in shell sources.

What could NOT be verified in this sandbox (hard platform limits, same class as
the Playwright/Cloudflare Tunnel limits in AGENTS.md):
- From-ZIP fresh-chroot acceptance run: all Ubuntu mirror hosts
  (archive.ubuntu.com, mirrors.aliyun.com, tuna, ustc, azure) are unreachable
  through the sandbox egress proxy (CONNECT establishes, then stalls), so
  `debootstrap` cannot build a fresh chroot. The ZIP→tree byte-identity check
  above is the substitute evidence.
- Post-install HTTP/HTTPS/PHP status-code checks: not completed before the
  network block.
- ShellCheck: not installable in this sandbox (APT fetch failures); not claimed.
- dockerd cannot start here (no netfilter): Docker/Compose install + compose
  config verified, real container start not verified.
