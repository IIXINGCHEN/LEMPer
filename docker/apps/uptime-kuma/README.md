# Uptime Kuma

Self-hosted uptime / service monitoring. Complements Monit (which watches the
host itself): Uptime Kuma watches your *services* — HTTP endpoints, ping,
DNS, TCP ports — from the outside in.

- Default port: **3001** → open `http://<server-ip>:3001` after install
- First visit creates the admin account in the web UI (no default password)
- Data persists in `/home/docker/uptime-kuma/data`

## Reverse proxy via LEMPer nginx

Create a vhost (e.g. `lemper-cli site add status.example.com`) and proxy to it:

```nginx
location / {
    proxy_pass http://127.0.0.1:3001;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
}
```

Then issue a Let's Encrypt cert for the domain as usual.
