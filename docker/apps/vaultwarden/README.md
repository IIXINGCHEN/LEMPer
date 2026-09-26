# Vaultwarden

Self-hosted password manager, compatible with official Bitwarden clients
(browser extensions, mobile apps, desktop). LEMPer has nothing like it
natively, which is why it's in the curated market.

- Default port: **8000** → open `http://<server-ip>:8000` after install
- Admin panel: `http://<server-ip>:8000/admin` (token from install output)
- Sign-ups are **disabled by default**; create users from the admin panel
- Data persists in `/home/docker/vaultwarden/data`

## Reverse proxy via LEMPer nginx (strongly recommended — enables HTTPS)

Create a vhost (e.g. `lemper-cli site add vault.example.com`) and proxy to it:

```nginx
location / {
    proxy_pass http://127.0.0.1:8000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

Then issue a Let's Encrypt cert. Set `DOMAIN=https://vault.example.com` in the
app's `.env` afterwards so 2FA and email links work correctly.

## WebSocket notifications (optional)

For live sync, also proxy `/notifications/hub`:

```nginx
location /notifications/hub {
    proxy_pass http://127.0.0.1:8000;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}
```
