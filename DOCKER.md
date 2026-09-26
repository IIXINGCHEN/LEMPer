# Docker in LEMPer

LEMPer is a native LEMP stack installer first. Docker support exists for one
reason: some workloads are genuinely better as containers (a password manager,
an external uptime monitor). It is a thin, opt-in layer — not a panel, not a
second stack.

## Philosophy: complementary only

| kejilion/sh idea | LEMPer stance |
|---|---|
| Docker Engine install | ✅ Implemented (`INSTALL_DOCKER`) |
| Container management | ✅ Thin CLI wrapper (`lemper docker ...`, alias of `lemper-cli`) |
| One-click app market | ✅ Curated: 2 apps that fill real gaps (below) |
| LDNMP one-click stack | ❌ Redundant — LEMPer *is* the LEMP stack |
| BBR | ✅ Separate toggle (`ENABLE_BBR`), not Docker-specific |
| System info / speed test | ❌ Redundant — `lemper-cli bench` exists |
| Backup / migration | ❌ Redundant — Restic + Mariabackup exist |
| Web panel (KPanel etc.) | ❌ Obtrusive — LEMPer is CLI-first by design |

## Curated market

Only apps that (a) fill a gap LEMPer has nothing for, and (b) never fight
LEMPer for ports 80/443:

| App | What | Host port |
|---|---|---|
| uptime-kuma | Service/uptime monitoring (complements Monit, which watches the host) | 3001 |
| vaultwarden | Self-hosted password manager (Bitwarden-compatible) | 8000 |

Deliberately excluded: `nginx-proxy-manager` (binds 80/443 — conflicts with
LEMPer nginx), WordPress (LEMPer serves PHP natively, no container needed),
hosting panels, games, AI proxies.

All images are **pinned** (`louislam/uptime-kuma:2.5.5`,
`vaultwarden/server:1.37.3`) — never `:latest`. Data lives under
`/home/docker/<app>` (kejilion's sane convention).

## Usage

```bash
# Install Docker Engine + Compose (or set INSTALL_DOCKER=true and re-run install.sh)
# Then:
lemper-cli docker list
lemper-cli docker install uptime-kuma
lemper-cli docker install vaultwarden   # prints generated ADMIN_TOKEN once
lemper-cli docker ps
lemper-cli docker logs vaultwarden
lemper-cli docker uninstall uptime-kuma [--purge]
```

## Reverse proxy via LEMPer nginx (recommended)

Never expose container ports directly. All bundled compose files bind their
host ports to **127.0.0.1 only** — Docker inserts iptables rules ahead of UFW,
so a `0.0.0.0` publish would silently bypass the firewall. Keep it that way;
if you need public access, create a vhost and proxy to the container, then
issue a Let's Encrypt cert as usual:

> **Uptime Kuma first run:** the first visitor to reach it creates the admin
> account ("admin setup hijack"). Complete that step over the nginx HTTPS
> vhost above before the URL is reachable from anywhere untrusted.

```nginx
# uptime-kuma
location / {
    proxy_pass http://127.0.0.1:3001;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
}

# vaultwarden
location / {
    proxy_pass http://127.0.0.1:8000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

## Registry mirror (China, optional)

Docker Hub can be slow from China. Set a mirror **you operate or trust** in
`.env` — LEMPer never hardcodes a third-party mirror (they come and go):

```bash
DOCKER_REGISTRY_MIRROR="https://your-mirror.example.com"
```

Written to `/etc/docker/daemon.json` only when set. The Docker *APT repo*
itself already switches to the Aliyun mirror automatically when
`MIRROR_REGION=cn`.
