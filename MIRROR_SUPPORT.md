# LEMPer Download Mirror Support

LEMPer automatically detects whether the server is on a China network or an
international network, and routes **all** software dependency downloads through
the fastest corresponding mirrors.

## How region detection works

Implemented in `scripts/lemper-mirrors.sh`, loaded once by `scripts/utils.sh`
(right after the `.env` file is parsed), so every installer script — including
individually run `scripts/install_*.sh` — gets it automatically.

1. `MIRROR_REGION` from `.env` is honored first:
   - `cn` → China mirrors, no network probing at all.
   - `global` → official upstream sources, no probing (previous default behavior).
   - `auto` (default) → probe and decide.
2. Auto mode probes two endpoints with 3s timeouts (worst case ~6s total):
   - domestic: `https://mirrors.tuna.tsinghua.edu.cn`
   - international: `https://github.com`
3. Decision:
   - only domestic reachable → `cn`
   - only international reachable → `global`
   - both reachable → whichever answered faster (ties → `global`)
   - neither reachable / curl missing → `global` (safe default = old behavior)
4. The result is cached in `LEMPER_REGION` for the process; detection never
   aborts the installer and never returns a failure status.

Test hooks: `LEMPER_CN_PROBE`, `LEMPER_GLOBAL_PROBE`, `LEMPER_PROBE_TIMEOUT`
env vars override the probe endpoints/timeout (used by the unit tests).

## How mirrors are applied

- `lemper_init_mirrors()` exports one base-URL variable per source
  (`MONGODB_REPO_BASE`, `PGDG_REPO_BASE`, `PYTHON_DL_BASE`, `GO_DL_BASE`,
  `COMPOSER_INSTALLER_URL`, `PIP_INDEX_URL`, `BORINGSSL_BASE`, …). Global
  values are byte-identical to the previously hardcoded URLs, so the
  international install path is unchanged.
- `mirror_url <key>` returns the regional base for a source key.
- `gh_url <url>` rewrites `github.com` / `raw.githubusercontent.com` URLs
  through the optional `GITHUB_PROXY` prefix (opt-in; empty by default, so
  GitHub is used directly unless the user configures a proxy).
- `lemper_apply_apt_mirrors()` rewrites official Ubuntu/Debian archive hosts
  in `/etc/apt/sources.list*` to the China mirror when region is `cn`.
  It is idempotent and a no-op in `global` mode. Called from `install.sh`
  (after `init_config`) and from `scripts/install_dependencies.sh` (so
  standalone runs are covered too).
- MariaDB reuses the existing `MYSQL_REPO_MIRROR_URL` mechanism: when empty
  and region is `cn`, it defaults to the verified Aliyun MariaDB repo mirror.
- `PIP_INDEX_URL` is exported; `pip` honors it natively (get-pip.py, certbot
  venv installs, and the Python source-build step).

## Mirror mapping table

All China mirror URLs below were verified with HTTP checks on 2026-09-24.

| Source | Global (official) | China mirror |
|---|---|---|
| Ubuntu/Debian APT archives | `archive.ubuntu.com`, `security.ubuntu.com`, `ports.ubuntu.com`, `deb.debian.org`, `security.debian.org` | `https://mirrors.tuna.tsinghua.edu.cn` (+ `/ubuntu`, `/debian`, `/debian-security`, `/ubuntu-ports`); overridable via `APT_MIRROR_URL` |
| MariaDB APT repo | `downloads.mariadb.com` (repo_setup) | `https://mirrors.aliyun.com/mariadb` (via `MYSQL_REPO_MIRROR_URL`) |
| PostgreSQL PGDG APT | `https://apt.postgresql.org/pub/repos/apt` | `https://mirrors.aliyun.com/postgresql/repos/apt` |
| MongoDB APT | `https://repo.mongodb.org/apt` | `https://mirrors.tuna.tsinghua.edu.cn/mongodb/apt` |
| Python source | `https://www.python.org/ftp/python` | `https://registry.npmmirror.com/-/binary/python` |
| Go toolchain | `https://go.dev/dl` | `https://mirrors.aliyun.com/golang` |
| Composer installer | `https://getcomposer.org/installer` | `https://install.phpcomposer.com/installer` |
| PyPI (pip index) | `https://pypi.org/simple` | `https://mirrors.aliyun.com/pypi/simple/` |
| BoringSSL source | `https://boringssl.googlesource.com/boringssl/+archive/refs/heads` | `https://github.com/google/boringssl/archive/refs/heads` (official GitHub mirror) |
| GitHub / raw.githubusercontent.com (all releases, git clones) | direct | direct, or via optional `GITHUB_PROXY` prefix |

## Sources with no China mirror (kept on official URLs, documented)

No official/reliable China mirror exists for these; inventing one would be
worse than using the (usually reachable) upstream. They are wired through
named variables anyway so a mirror can be dropped in later:

| Source | Reason |
|---|---|
| `packages.sury.org` (ondrej PHP / Nginx) | No CN mirror; `SURY_BASE` variable |
| `deb.myguard.nl` (MyGuard Nginx) | No CN mirror; `MYGUARD_BASE` variable |
| Launchpad PPAs (`ppa.launchpadcontent.net`, `ppa:…` via add-apt-repository: openswoole, maxmind, deadsnakes, longsleep golang-backports, certbot) | Launchpad has no CN mirror |
| `packages.redis.io` / `download.redis.io` (Redis) | No CN mirror; `REDIS_REPO_BASE` / `REDIS_DL_BASE` variables |
| `nginx.org/download` (Nginx source) | No CN mirror; `NGINX_DL_BASE` variable |
| `nginx.org/packages` (Nginx official APT repo, stable branch) | No CN mirror; upstream kept as-is |
| `memcached.org` (Memcached source) | No CN mirror |
| `ftp.openbsd.org` (LibreSSL) | No CN mirror |
| `download.pureftpd.org` | Not used (GitHub release is used instead) |
| `security.appspot.com` (vsftpd) | Google App Engine, no CN mirror |
| `download.maxmind.com` (GeoLite2) | Authenticated per-license download, no mirror |
| `download.configserver.com` (CSF) | No CN mirror |
| `pecl.php.net` | No CN mirror (usually reachable from CN) |
| GPG signing keys (`mariadb.org`, `postgresql.org`, `mongodb.org`, `composer.github.io`) | Tiny files, kept on official hosts |

NodeSource (`deb.nodesource.com`) is not used by the installer
(`scripts/install_nodejs.sh` is currently a stub), so no mapping was added.

## Files changed

- **New:** `scripts/lemper-mirrors.sh` — detection, mirror map, helpers.
- `scripts/utils.sh` — sources the mirror lib after `.env` load, runs detection.
- `install.sh` — applies China APT mirrors after `init_config`.
- `.env.dist`, `.env` — new `[mirrors]` section
  (`MIRROR_REGION`, `APT_MIRROR_URL`, `GITHUB_PROXY`).
- `README.md` — new "Download Mirrors" section.
- Wired per-source URLs (global behavior unchanged) in:
  `scripts/install_dependencies.sh` (Python source, APT mirrors),
  `scripts/install_postgres.sh`, `scripts/install_mongodb.sh`,
  `scripts/install_redis.sh`, `scripts/install_php.sh` (Sury, Composer,
  php-loaders), `scripts/install_phalcon.sh`,
  `scripts/install_fail2ban.sh`, `scripts/install_imagemagick.sh`,
  `scripts/install_pureftpd.sh`, `scripts/install_tools.sh`,
  `scripts/install_memcached.sh` (no change needed — no CN mirror),
  `scripts/install_vsftpd.sh` (no change needed — no CN mirror),
  `scripts/server_security.sh` (APF GitHub URL),
  `scripts/nginx/nginx_repo.sh` (Sury, MyGuard),
  `scripts/nginx/nginx_build.sh`, `scripts/nginx/nginx_ssl_builders.sh`
  (OpenSSL, BoringSSL, Go, PCRE2), `scripts/nginx/nginx_common.sh`
  (`clone_or_update_repo` applies `gh_url`), `scripts/nginx/nginx_extra_modules.sh`
  (direct git clones).

## Validation

- `bash -n` passes on all 25 modified/new shell files.
- Detection unit checks: forced `cn`/`global` modes resolve all mirror
  variables to the expected URLs; auto mode with stubbed probes returns `cn`
  when only the domestic endpoint answers, `global` when neither answers;
  worst-case probe time stays under ~6s (measured 0.8s–6s depending on
  network); never hangs, never fails the installer.
- Offline chroot smoke test (`~/workspace/LEMPer-test/rootfs`): sourcing
  `scripts/utils.sh` falls back to `global` in ~0.1s; `MIRROR_REGION=cn`
  correctly rewrites a test `sources.list.d` entry to Tsinghua URLs
  (idempotent re-runs are no-ops); existing entries (e.g. the local test
  repo) are untouched.
