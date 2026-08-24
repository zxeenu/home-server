# Home Server Stack

A Docker Compose setup for an old PC turned home server: DNS + ad-blocking, media streaming, torrent downloads, PDF tools, an ebook library, push notifications, network file browsing, a reverse proxy for clean domain names, container management, and a landing page listing it all.

## What's included

| Service | What it does | Domain (once configured) | Direct fallback |
|---|---|---|---|
| Homepage | Static dashboard linking to everything | `home.lan` | `:8888` |
| Nginx Proxy Manager | Routes domain names to the right container | `proxy.home.lan` | `:81` |
| Portainer | Web UI to manage all containers | `portainer.home.lan` | `:9000` |
| Pi-hole | Network-wide DNS + ad blocking | `pihole.home.lan` | `:8081/admin` |
| Plex | Media server | `plex.home.lan` | `:32400/web` |
| qBittorrent | Torrent client | `torrent.home.lan` | `:8080` |
| Stirling PDF | PDF toolkit (merge, split, OCR, convert, compress) | `pdf.home.lan` | `:8082` |
| Calibre-Web | Ebook library & web reader | `books.home.lan` | `:8083` |
| ntfy | Push notifications to phone/desktop | `ntfy.home.lan` | `:8084` |
| Samba | Network file share (browse/clean up media) | `files.home.lan` | `\\<server-ip>\media` |

Sonarr, Radarr, and Prowlarr (automated TV/movie fetching) are in `docker-compose.yml` but **commented out**. Uncomment them if you want that later — see the note at the bottom.

## Files in this folder

- `docker-compose.yml` — defines all the services
- `.env.example` — template for your settings (copy to `.env`)
- `index.html` — the homepage dashboard
- `setup.sh` — creates all the folders these services expect

## What you need before starting

- Docker and Docker Compose installed on the server
- Your server's **LAN IP address** — run `hostname -I` and pick the one matching your router's subnet (e.g. `192.168.1.x`)
- That IP **reserved as a static lease** in your router's DHCP settings, so it never changes
- Enough free storage for `/srv/media` (or wherever you point `MEDIA`)

## Setup

```bash
# 1. Make the setup script executable and run it (needs sudo - /srv is root-owned)
chmod +x setup.sh
sudo ./setup.sh

# 2. Edit your settings (SERVER_IP is auto-filled - just double-check it's right)
nano .env

# 3. Start everything
docker compose up -d
```

`setup.sh` creates the appdata/media folder structure, creates `.env` from the example (auto-detecting and pre-filling your server's LAN IP as `SERVER_IP`), and hands ownership of the folders back to your user (so Docker containers can actually write to them) — it won't overwrite files that already exist, so it's safe to re-run.

Pi-hole's local DNS records (`home.lan`, `plex.home.lan`, etc.) are set directly in `docker-compose.yml` via the `FTLCONF_dns_hosts` environment variable, using `SERVER_IP` from `.env` — no separate file to manage. Pi-hole v6 dropped support for the old `custom.list` file, so this is the current supported way to do it.

## After it's running

1. **Nginx Proxy Manager** (`http://<server-ip>:81`) — first login is `admin@example.com` / `changeme`, you'll be forced to change it. Add a Proxy Host for each domain in `custom.list`, pointing to the matching container name and internal port:
   - `plex.home.lan` → server IP (not `plex` — Plex uses host networking) : `32400`
   - `torrent.home.lan` → `qbittorrent` : `8080`
   - `pdf.home.lan` → `stirlingpdf` : `8080`
   - `books.home.lan` → `calibreweb` : `8083`
   - `ntfy.home.lan` → `ntfy` : `80`
   - `portainer.home.lan` → `portainer` : `9000`
   - `pihole.home.lan` → `pihole` : `80`
   - `home.lan` → `homepage` : `80`
   - `proxy.home.lan` → `nginxproxymanager` : `81`

2. **Pi-hole** (`http://<server-ip>:8081/admin`) — check Settings → Local DNS Records to confirm the `.home.lan` entries loaded from `FTLCONF_dns_hosts`.

3. **Router** — set the primary DNS server (in DHCP settings) to your server's IP, with a public DNS like `1.1.1.1` as secondary fallback. This makes every device on the WiFi resolve the `.home.lan` domains automatically, no per-device setup needed.

4. Visit `http://home.lan` from any device on the network — you should see the dashboard with links to everything.

## Notes

- **`.home.lan` isn't a real public domain**, so browsers will show an "insecure" HTTPS warning unless you set up local trusted certs later in Nginx Proxy Manager. Fine to click through for personal use.
- **If the server goes down**, `.home.lan` domains stop resolving (Pi-hole is what serves them). General internet browsing keeps working via the secondary DNS fallback. Use the direct `<server-ip>:port` fallbacks in the table above if needed.
- **ntfy has no auth by default** — anyone who can reach it can read/write any topic. Fine on a trusted LAN, but if you proxy `ntfy.home.lan` out to the internet, lock it down first: `sudo docker exec -it ntfy ntfy user add --role=admin <you>`, then set `auth-default-access: deny-all` in a `server.yml` mounted at `/etc/ntfy`.
- **To enable Sonarr/Radarr/Prowlarr later**: uncomment their blocks in `docker-compose.yml`, add their domains to the `FTLCONF_dns_hosts` block in the Pi-hole service, run `docker compose up -d` again, then add Proxy Hosts for them in Nginx Proxy Manager and rows in `index.html` if you want them on the dashboard.
- Don't commit `.env` to version control — it holds your Pi-hole and Samba passwords.
- `sudo docker compose up -d --force-recreate pihole` recreate pi hole if issues arise
- `sudo docker exec -it pihole pihole setpassword` change password of pi hole
- `sudo docker logs qbittorrent | grep -i password` qbittorrent works after this
- `sudo docker restart nginxproxymanager` after adding new services, if they dont resolve right. restart npm
- `ip route | grep -v default` get subnets for tailscale
- `sudo chown -R 1000:1000 /srv/media/books` if the books folder does not have write access. 
- `sudo --preserve-env=NPM_EMAIL,NPM_PASSWORD bash npm-export.sh` run the npm export script with envs from the .zshrc
- `bash generate-npm-config.sh` run the config generator to read from env and generate initial nginx proxy manager profile. run this after making a user accoount. Use `sudo chown -R "$USER:$USER" ../config` if you are unable to write to the config folder. 
- `bash npm-import.sh` run the import after generating the config generator


## Minecraft
Plugin urls if needed
https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot
https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot


## ACME Certificate Renewal Hook

The server uses `acme.sh` to obtain and renew the wildcard certificate for
`DOMAIN_NAME`.

When the certificate is renewed, `acme.sh` executes a standalone hook which
uploads the renewed certificate to Nginx Proxy Manager.

### Hook architecture

The source hook lives in the repository:

    scripts/npm-cert-update.sh

The actual hook executed by `acme.sh` is copied to the user's home directory.

For example, with:

    DOMAIN_NAME=eggbase.net

the installed hook is:

    ~/eggbase.net-npm-cert-update.sh

The deployment flow is:

    scripts/npm-cert-update.sh
              |
              | configure-acme-hook.sh
              v
    ~/eggbase.net-npm-cert-update.sh
              |
              | registered with acme.sh
              v
    certificate renewal
              |
              v
    Nginx Proxy Manager certificate update

### Configure the hook

Make sure `DOMAIN_NAME` is set in `.env`:

    DOMAIN_NAME=eggbase.net

Then run:

    ./scripts/configure-acme-hook.sh

This will:

1. Read `DOMAIN_NAME` from `.env`.
2. Copy `scripts/npm-cert-update.sh` to
   `~/${DOMAIN_NAME}-npm-cert-update.sh`.
3. Set the installed hook permissions to `700`.
4. Register the installed hook as the `acme.sh` reload hook.
5. Keep the renewal hook independent from the Git repository.

### Check the current configuration

Run:

    ./scripts/configure-acme-hook.sh --check

This displays the configured domain, source script, installed hook,
permissions, acme.sh reload hook, and certificate paths.

### Updating the renewal hook

If `scripts/npm-cert-update.sh` is changed, run:

    ./scripts/configure-acme-hook.sh

This copies the updated hook to the domain-specific location and re-registers
it with `acme.sh`.

There is no need to manually edit files inside `~/.acme.sh/`.

### Testing the hook

The installed hook can be run directly.

For `DOMAIN_NAME=eggbase.net`:

    ~/eggbase.net-npm-cert-update.sh

The hook uploads the current certificate from:

    ~/.acme.sh/${DOMAIN_NAME}_ecc/

to Nginx Proxy Manager.

The Nginx Proxy Manager certificate is located by its `nice_name` rather than
by a hardcoded certificate ID.