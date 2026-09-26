# LEMPer LTS Policy

> Last reviewed: 2026-09-25

LEMPer targets **production servers**. This document defines which version line
each dependency follows and why. The guiding principle:

- Prefer **long-term-supported** release lines over the newest feature releases.
- A "newest stable" version is only chosen when the software has no LTS concept
  or when the newest line *is* the LTS line.

## Version matrix

| Software | Before (latest) | Now (LTS) | Support status |
|---|---|---|---|
| PHP (default) | 8.5 | **8.4** | Security fixes until 31 Dec 2028 (php.net) |
| PHP (offered) | 8.3, 8.4, 8.5 | 8.3, 8.4, 8.5 | 8.3 → 31 Dec 2027; 8.5 → 31 Dec 2029 |
| Nginx | 1.31.x mainline (myguard) | **1.30.x stable** (nginx.org official repo) | Stable branch: critical fixes only |
| MariaDB | 13.0 (rolling, **not LTS**) | **12.3 LTS** | Community maintenance until June 2029 |
| PostgreSQL | 18 | 18 (unchanged) | 5-year support until Sep 2030 |
| MongoDB | 8.0 | 8.0 (unchanged) | 8.0 is the LTS release |
| OpenSSL | 3.5.8 | 3.5.8 (unchanged) | 3.5 is LTS until Apr 2030 |
| Python (Ubuntu 24.04) | 3.14 (deadsnakes PPA) | **3.12** (distro) | Supported with Ubuntu 24.04 until 2029 |
| Redis | latest stable | latest stable | No LTS concept |
| Go | latest stable | latest stable | Go supports last 2 releases only |
| Composer / Fail2ban / Phalcon / ImageMagick | latest stable | latest stable | No LTS concept |

## Rationale per software

### PHP 8.4 (default)
PHP has no official "LTS" designation; each branch gets 2 years active + 2 years
security support. PHP 8.4 (released Nov 2024) receives security fixes until
**31 Dec 2028** and is the most broadly compatible modern branch across the
WordPress/Laravel/Symfony ecosystem. PHP 8.5 stays available as an option for
those who want it, but it is no longer the default. Default FPM socket paths in
the bundled vhosts now point to `php8.4-fpm.sock`.

### Nginx 1.30.x stable (official nginx.org repo)
Nginx maintains two branches: **mainline** (odd minor, e.g. 1.31.x — new
features) and **stable** (even minor, e.g. 1.30.x — critical bug/security fixes
only). The previous default pulled mainline 1.31.5 from the third-party myguard
repo (which offers no stable branch). The installer now defaults to
`NGINX_REPO_SRC=official`, i.e. the **official nginx.org APT repository,
stable branch** (currently 1.30.5), which is the canonical LTS-aligned source.
`NGINX_VERSION=stable` resolves to the 1.30.x line. Repo layout per
https://nginx.org/en/linux_packages.html: stable lives at
`https://nginx.org/packages/<distro>`, mainline at
`https://nginx.org/packages/mainline/<distro>`.

Module note: nginx.org ships a smaller set of dynamic modules
(`nginx-module-geoip`, `-image-filter`, `-xslt`, `-njs`, `-perl`, `-otel`;
stream and mail are compiled into the official binary). Third-party modules not
shipped by nginx.org (brotli, cache-purge, headers-more, vts, fancyindex,
subs-filter, auth-pam, …) are skipped with a warning on the repo path — use
`NGINX_INSTALLER=source` (which builds 1.30.5 with the full module set) if you
need them.

### MariaDB 12.3 LTS
MariaDB 13.0 is a **rolling release** (supported ~3 months), unsuitable for
production. MariaDB designates one LTS per year (Q2 release), each maintained
for years. As of Sep 2026 the maintained LTS lines are 12.3 (until **June
2029**), 11.8 (until June 2028), 11.4 and 10.11. LEMPer now defaults to
**12.3 LTS** — the current LTS and MariaDB's own recommendation for new
deployments wanting the longest runway. The repo setup (official
`mariadb_repo_setup`, or the Aliyun mirror for region=cn) is version-agnostic;
only the default changed (`MYSQL_VERSION=12.3`).

### PostgreSQL 18
PostgreSQL has no LTS label; every major release is supported for 5 years.
PostgreSQL 18 (Sep 2025) is supported until **Sep 2030** — kept.

### MongoDB 8.0
8.0 is MongoDB's designated LTS release — kept.

### OpenSSL 3.5.8
OpenSSL 3.5 is a long-term-support branch (until Apr 2030) — kept.

### Python 3.12 (Ubuntu 24.04)
Python in LEMPer is tooling (Certbot venv, helpers), not the app runtime.
Ubuntu 24.04 ships **Python 3.12**, supported with the distro until **2029**.
There is no need for the deadsnakes PPA's 3.14 on noble, so noble now uses the
distro Python. (Focal/Jammy keep deadsnakes 3.14 since their distro Pythons are
older; the from-source fallback now builds `DEFAULT_PYTHON_VERSION=3.12.12`.)

### Kept at latest stable (no LTS concept)
Redis, Go (only the last two releases are supported upstream), Composer,
Fail2ban, Phalcon, ImageMagick — latest stable remains the correct choice.
Node.js is not installed by LEMPer.

## Changing a default
All of the above are `.env` defaults, not hard requirements. Override per
deployment, e.g.:

```bash
./lemper-env.sh init --default-php 8.5 --db mariadb:11.8 --yes
```
