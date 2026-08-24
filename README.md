# Home Server Stack

A fully reproducible Docker Compose setup for a personal media server: DNS + ad-blocking, media streaming, torrent downloads, PDF tools, an ebook library, push notifications, network file browsing, a reverse proxy with automatic HTTPS, and Minecraft server — all pinned to specific versions and accessible locally and remotely via Tailscale.

## Features

✅ **Infrastructure-as-Code** — Version-controlled, reproducible deployment  
✅ **Pinned Container Images** — No surprises from `latest` tag updates  
✅ **Automated Setup** — One script creates folders, generates `.env`, auto-detects server IP  
✅ **HTTPS with Auto-Renewal** — ACME/Let's Encrypt integration via acme.sh hook  
✅ **Local DNS** — All services accessible via `.home.lan` domains on your network  
✅ **Remote Access** — Tailscale VPN integration for accessing services anywhere  
✅ **Easy Maintenance** — Portainer web UI for container management  

## What's Included

| Service | Purpose | Domain (local) | Direct fallback | Notes |
|---|---|---|---|---|
| **Homepage** | Static dashboard linking to everything | `home.lan` | `:8888` | Static HTML landing page |
| **Nginx Proxy Manager** | Routes domain names → containers, HTTPS termination | `proxy.lan` | `:81` | Manages certs, proxy hosts, SSL |
| **Portainer** | Docker container management UI | `portainer.lan` | `:9000` | Monitor/manage all services |
| **Pi-hole** | Network-wide DNS + ad blocking | `pihole.lan` | `:8081/admin` | Blocks ads for entire LAN |
| **Plex** | Media server (movies, TV, music) | `plex.lan` | `:32400/web` | Streams media locally + remotely |
| **qBittorrent** | Torrent client | `torrent.lan` | `:8080` | Download manager with web UI |
| **Stirling PDF** | PDF toolkit (merge, split, OCR, compress) | `pdf.lan` | `:8082` | Full PDF manipulation suite |
| **Calibre-Web** | Ebook library & web reader | `books.lan` | `:8083` | Browse/read ebooks from browser |
| **ntfy** | Push notifications to phone/desktop | `ntfy.lan` | `:8084` | Send alerts from scripts |
| **Samba** | Network file share (SMB) | `files.lan` | `\\<server-ip>\media` | Browse/manage media over LAN |
| **Tailscale** | WireGuard VPN for remote access | — | — | Access everything from anywhere |
| **Minecraft** | Minecraft server (Java + Bedrock via Geyser) | `minecraft.lan` | `:25565` / `:19132` | Multi-platform Minecraft server |

**Optional (commented out by default):**
- **Sonarr** — Automated TV show fetching
- **Radarr** — Automated movie fetching
- **Prowlarr** — Indexer manager for Sonarr/Radarr

## Prerequisites

- **Docker & Docker Compose** installed on your server
- **Linux system** (tested on Ubuntu, should work on any distro)
- **Server's LAN IP address** — run `hostname -I` and pick the subnet match (e.g., `192.168.1.50`)
- **Static DHCP lease** in your router for that IP (prevents DNS issues)
- **Free storage** for `/srv/media` — minimum 100GB for media, or as much as you have
- **Tailscale account** (free tier) for remote access
- **acme.sh** (optional) if you want automatic HTTPS certificate renewal

## Quick Start

### 1. Clone and Setup

```bash
git clone https://github.com/zxeenu/home-server-setup.git
cd home-server-setup

# Make the setup script executable and run it (needs sudo for /srv)
chmod +x scripts/setup.sh
sudo ./scripts/setup.sh
```

The setup script:
- Creates folder structure at `/srv/appdata` and `/srv/media`
- Generates `.env` from `.env.example` (first run only)
- Auto-detects and pre-fills your server's LAN IP as `SERVER_IP`
- Hands folder ownership back to your user

### 2. Configure

```bash
# Edit .env and verify settings (at minimum: SERVER_IP, TZ, passwords)
nano .env
```

Key variables:
```bash
SERVER_IP=192.168.1.50          # Your server's LAN IP (auto-detected)
DOMAIN_NAME=home.lan            # Domain suffix for all services
TZ=America/New_York             # Your timezone
PUID=1000                        # User ID for containers
PGID=1000                        # Group ID for containers
PIHOLE_PASSWORD=changeme        # Pi-hole admin password
SMB_USER=media                  # Samba username
SMB_PASSWORD=changeme           # Samba password
TS_AUTHKEY=tskey_abc123...      # Tailscale auth key (from https://login.tailscale.com/admin/settings/keys)
MC_TYPE=spigot                  # Minecraft server type (spigot, paper, purpur, etc.)
MC_VERSION=latest               # Minecraft version
MC_MEMORY=2048                  # Minecraft server RAM in MB
```

### 3. Start the Stack

```bash
docker compose up -d
```

Check status:
```bash
docker compose ps
```

## Post-Deployment

### 1. Configure Nginx Proxy Manager

Visit `http://<server-ip>:81` (e.g., `http://192.168.1.50:81`)

**First login:** `admin@example.com` / `changeme` → you'll be forced to change it

**Add Proxy Hosts** for each service. The config generator script can help:

```bash
bash scripts/generate-npm-config.sh
```

This generates a JSON template you can import into Nginx Proxy Manager. Alternatively, manually add:

| Domain | Forward Host | Forward Port | SSL |
|---|---|---|---|
| `home.home.lan` | `homepage` | `80` | Yes |
| `proxy.home.lan` | `nginxproxymanager` | `81` | Yes |
| `portainer.home.lan` | `portainer` | `9000` | Yes |
| `pihole.home.lan` | `pihole` | `80` | Yes |
| `plex.home.lan` | `<server-ip>` | `32400` | Yes |
| `torrent.home.lan` | `qbittorrent` | `8080` | Yes |
| `pdf.home.lan` | `stirlingpdf` | `8080` | Yes |
| `books.home.lan` | `calibreweb` | `8083` | Yes |
| `ntfy.home.lan` | `ntfy` | `80` | Yes |
| `minecraft.home.lan` | `<server-ip>` | `25565` | Yes |

### 2. Configure Pi-hole DNS

Visit `http://<server-ip>:8081/admin`

- Go to **Settings → Local DNS Records** and verify that `.home.lan` entries are present (they're injected via `FTLCONF_dns_hosts` in the compose file)
- Set your **router's DHCP DNS** to your server's IP (primary) with a fallback like `1.1.1.1` (secondary)

Now all devices on your WiFi will resolve `*.home.lan` and have ads blocked.

### 3. Configure Tailscale

On your server:
```bash
# Check Tailscale status
docker exec tailscale tailscale status
```

**On your devices** (phone, laptop, etc.):
- Install Tailscale from your app store
- Sign in with the same account
- You'll see your server in the machine list; connect to it

Now you can access `http://home.home.lan:8888` (or any direct port) from anywhere via your Tailnet.

### 4. (Optional) Setup HTTPS with Auto-Renewal

If you have a real domain (e.g., `example.com`) and want automatic certificate renewal:

```bash
# Install acme.sh (if not already installed)
curl https://get.acme.sh | sh

# Configure the ACME hook (generates ~/example.com-npm-cert-update.sh)
bash scripts/configure-acme-hook.sh

# Request a certificate from Let's Encrypt
~/.acme.sh/acme.sh --issue -d example.com -d '*.example.com' --dns dns_route53
# (replace dns_route53 with your DNS provider's acme.sh plugin)
```

The hook will automatically upload renewed certificates to Nginx Proxy Manager every 60 days.

## Project Structure

```
home-server-setup/
├── docker-compose.yml          # Main service definitions (pinned images)
├── .env.example                # Template for .env (copy to .env, don't commit)
├── index.html                  # Homepage dashboard
│
├── scripts/
│   ├── setup.sh                # Initialize folders and .env (run once)
│   ├── configure-acme-hook.sh  # Register acme.sh certificate renewal hook
│   ├── generate-npm-config.sh  # Generate Nginx Proxy Manager config from .env
│   ├── npm-cert-update.sh      # Upload renewed certs to NPM (called by acme.sh)
│   └── npm-import.sh           # Import npm-config.json into Nginx Proxy Manager
│
├── subsetup/
│   ├── minecraft/              # Minecraft server compose (optional separate stack)
│   └── minecraft-tailscale/    # Tailscale sidecar for Minecraft
│
└── README.md                   # This file
```

## Scripts Guide

### `setup.sh`
**Purpose:** One-time initialization of folder structure and `.env` file.

```bash
sudo ./scripts/setup.sh
```

**What it does:**
- Creates `/srv/appdata/{npm,portainer,pihole,...}` directories
- Creates `/srv/media/{movies,tv,downloads,books}`
- Copies `.env.example` → `.env` (if `.env` doesn't exist)
- Auto-detects server IP and pre-fills `SERVER_IP` in `.env`
- Sets correct ownership so containers can write to folders

**Key features:**
- Idempotent — safe to run multiple times
- Detects your server's LAN IP automatically
- Creates all subdirectories for every service
- Hands ownership to the sudo user so you can edit files

### `configure-acme-hook.sh`
**Purpose:** Register the certificate renewal hook with acme.sh.

```bash
bash scripts/configure-acme-hook.sh
```

**What it does:**
- Reads `DOMAIN_NAME` and `IP_ADDRESS` from `.env`
- Generates a standalone hook script at `~/<DOMAIN_NAME>-npm-cert-update.sh`
- Registers it with acme.sh via `--install-cert --reloadcmd`
- Injects variables into the hook so it doesn't need `.env` access
- Uses `printf %q` for safe variable escaping

**Requirements:**
- `DOMAIN_NAME` and `IP_ADDRESS` in `.env`
- acme.sh already installed at `~/.acme.sh/acme.sh`

**Output:** A standalone hook in your home directory that acme.sh calls on certificate renewal.

### `npm-cert-update.sh`
**Purpose:** Upload renewed ACME certificates to Nginx Proxy Manager.

```bash
# Called automatically by acme.sh on certificate renewal
# Can also be run manually:
bash ~/DOMAIN_NAME-npm-cert-update.sh
```

**What it does:**
- Reads certificate files from `~/.acme.sh/<DOMAIN_NAME>_ecc/`
- Authenticates to Nginx Proxy Manager via email/password
- Finds the certificate by "nice_name" (not ID, so it's stable)
- Uploads the new certificate
- Tries multiple NPM hosts (proxy domain + server IP) for redundancy
- Sends a notification to ntfy when successful

**Requirements:**
- `DOMAIN_NAME` and `IP_ADDRESS` embedded in the hook (from configure-acme-hook.sh)
- `NPM_EMAIL` and `NPM_PASSWORD` in environment (e.g., exported in `~/.zshrc`)
- `curl` and `jq` installed on host
- Certificate already exists in NPM with nice_name "HOME NETWORK CERT"

**ntfy Notifications:**
- Sends to `https://ntfy.<DOMAIN_NAME>/home-alerts` by default
- Notifies you when certs are renewed successfully

### `generate-npm-config.sh`
**Purpose:** Generate a complete Nginx Proxy Manager configuration from `.env`.

```bash
bash scripts/generate-npm-config.sh
```

**What it does:**
- Reads `DOMAIN_NAME` and `IP_ADDRESS` from `.env`
- Generates `config/npm-config.json` with all proxy hosts pre-configured
- Creates proxy hosts for all services (home, plex, books, pdf, etc.)
- Can be imported into Nginx Proxy Manager via the UI

**Output:** `config/npm-config.json` with:
- 9 pre-configured proxy hosts (books, home, ntfy, pdf, pihole, plex, portainer, proxy, torrent)
- SSL forced to true for all hosts
- Certificate name set to "HOME NETWORK CERT"
- WebSocket support enabled where needed

**Note:** The generated JSON is not version-controlled (it's in `.gitignore`).

## Image Pinning Strategy

All container images are pinned to their **exact image digest** (not version tags). This ensures:
- ✅ Reproducible deployments (same image always runs)
- ✅ No unexpected breaking changes from `latest`
- ✅ Explicit control over updates

**To update an image intentionally:**

```bash
# Pull newer images
docker compose pull

# Start with new images
docker compose up -d

# Inspect the new digest
docker inspect <container-name> | grep Digest

# Update docker-compose.yml with the new digest
nano docker-compose.yml
git add docker-compose.yml
git commit -m "Update <service> image to <new-digest>"
```

**Currently pinned versions:**
- Homepage: `nginx:alpine`
- Nginx Proxy Manager: `jc21/nginx-proxy-manager`
- Portainer: `portainer/portainer-ce`
- Pi-hole: `pihole/pihole` (v6)
- Plex: `lscr.io/linuxserver/plex` (v1.43.3)
- qBittorrent: `lscr.io/linuxserver/qbittorrent` (v5.2.3)
- Stirling PDF: `stirlingtools/stirling-pdf`
- Calibre-Web: `lscr.io/linuxserver/calibre-web`
- ntfy: `binwiederhier/ntfy`
- Samba: `dperson/samba`
- Tailscale: `tailscale/tailscale`
- Minecraft: `itzg/minecraft-server` (with Geyser + Floodgate plugins)

## Troubleshooting

### Domains not resolving (`.home.lan` doesn't work)

1. **Check Pi-hole DNS records:**
   ```bash
   docker exec pihole cat /etc/dnsmasq.d/local.list
   ```

2. **Check router DHCP settings:**
   - Primary DNS: your server IP (e.g., `192.168.1.50`)
   - Secondary DNS: `1.1.1.1` or `8.8.8.8`

3. **Verify from a client:**
   ```bash
   nslookup home.home.lan 192.168.1.50  # Should resolve to server IP
   ```

4. **Restart Pi-hole:**
   ```bash
   docker compose up -d --force-recreate pihole
   ```

### Service won't start / exits immediately

```bash
# Check logs
docker compose logs <service-name>

# Most common: folder permissions
sudo chown -R 1000:1000 /srv/media
sudo chown -R 1000:1000 /srv/appdata
```

### Pi-hole password reset

```bash
docker exec -it pihole pihole setpassword <new-password>
```

### Nginx Proxy Manager won't connect to services

```bash
# Verify container network
docker network inspect home-server-net

# Restart Nginx Proxy Manager
docker compose restart nginxproxymanager
```

### Minecraft server won't start

```bash
# Check Minecraft logs
docker compose -f subsetup/minecraft/docker-compose.yml logs minecraft

# Most common: needs EULA acceptance or more RAM
# Edit subsetup/minecraft/docker-compose.yml or .env and restart
```

### qBittorrent password

```bash
docker compose logs qbittorrent | grep -i password
```

### Books folder permission issues

```bash
sudo chown -R 1000:1000 /srv/media/books
sudo chmod -R 755 /srv/media/books
```

```bash
docker exec calibreweb chmod +x /usr/bin/kepubify
```

### Tailscale connection issues

```bash
# Check Tailscale status
docker exec tailscale tailscale status

# Verify Tailscale container has proper network access
docker compose logs tailscale
```

### ACME certificate renewal fails

```bash
# Test the hook manually
~/DOMAIN_NAME-npm-cert-update.sh

# Check acme.sh logs
cat ~/.acme.sh/acme.sh.log | tail -50

# Verify NPM credentials are exported
echo $NPM_EMAIL
echo $NPM_PASSWORD
```

## Tailscale Setup

### Initial Configuration

1. **Get an auth key:**
   - Visit https://login.tailscale.com/admin/settings/keys
   - Create a new auth key (can be single-use or reusable)
   - Copy it

2. **Add to `.env`:**
   ```bash
   TS_AUTHKEY=tskey_abc123_def456_ghi789
   ```

3. **Start Tailscale:**
   ```bash
   docker compose up -d tailscale
   ```

4. **Verify connection:**
   ```bash
   docker exec tailscale tailscale status
   ```

### Access Services Over Tailscale

Once connected to your Tailnet:

- **Direct IP access:** `http://<tailscale-ip>:8888` (homepage)
- **Via local DNS:** `http://home.home.lan:443` (if Tailscale DNS is configured)
- **Specific services:** `http://<tailscale-ip>:25565` (Minecraft)

### Tailscale for Minecraft

Minecraft runs in a separate compose stack with its own Tailscale sidecar:

```bash
cd subsetup/minecraft
docker compose up -d
```

This allows Minecraft to be on the Tailnet independently.

## Advanced

### Enable Optional Services (Sonarr/Radarr/Prowlarr)

1. **Uncomment the services** in `docker-compose.yml` (lines 210-257)

2. **Add DNS records** for them in Pi-hole environment block:
   ```yaml
   FTLCONF_dns_hosts: |
     ${SERVER_IP} prowlarr.${DOMAIN_NAME}
     ${SERVER_IP} sonarr.${DOMAIN_NAME}
     ${SERVER_IP} radarr.${DOMAIN_NAME}
     # ... existing entries ...
   ```

3. **Update setup.sh** to create their appdata folders:
   ```bash
   mkdir -p "$APPDATA/prowlarr" "$APPDATA/sonarr" "$APPDATA/radarr"
   ```

4. **Add proxy hosts** in Nginx Proxy Manager for each domain

5. **Restart:**
   ```bash
   docker compose up -d
   ```

### Backup Strategy

Since this is media storage (non-critical), backups are optional. If you want to backup configs:

```bash
# Backup all appdata (configs only, not media)
tar -czf appdata-backup-$(date +%Y%m%d).tar.gz /srv/appdata

# To restore:
tar -xzf appdata-backup-*.tar.gz -C /
```

For a **DAS (Direct Attached Storage)** setup:
- Mount DAS at `/mnt/storage` (or similar)
- Point media paths in `.env` to DAS mount
- Consider RAID for redundancy

### Plex Hardware Transcoding (Intel)

Uncomment the `devices` section in `docker-compose.yml` for Plex to use Quick Sync:

```yaml
plex:
  # ... existing config ...
  devices:
    - /dev/dri:/dev/dri
```

### Network File Share (Samba)

Access your media over SMB from Windows/Mac/Linux:

**Windows:**
```
\\<server-ip>\media
```

**Mac/Linux:**
```bash
mount -t cifs //<server-ip>/media /mnt/media -o username=<SMB_USER>,password=<SMB_PASSWORD>
```

**From .env:**
```bash
SMB_USER=media
SMB_PASSWORD=yourpassword
```

### Remote Access via Tailscale

Your home server is automatically part of your Tailnet. To use it remotely:

1. **Install Tailscale** on your device
2. **Sign in** with the same account
3. **Find your server** in the machine list (hostname: `home-server`)
4. **Connect to it** — all ports are now accessible

**Example:** Access Plex from a laptop at a friend's place:
```
http://home-server.YOUR-TAILNET:32400/web
```

## Secrets & Security Notes

- **`.env` is never committed** — it holds passwords and keys
- **Pi-hole password** is hashed inside the container; change it via the web UI
- **Samba is LAN-only by default** — if you expose it via Tailscale, restrict access
- **ntfy has no auth by default** — fine on trusted LAN, but secure if exposing to internet
- **NPM credentials** (`NPM_EMAIL`, `NPM_PASSWORD`) stored in shell for cert renewal only
- **Tailscale auth keys** should be single-use; generate new ones for each deployment
- **Don't share your `.env` file** — it contains all passwords and secrets

## Performance Tips

- **Plex:** Enable hardware transcoding (Intel/NVIDIA) for smooth streaming to multiple clients
- **Pi-hole:** Block lists are updated automatically; check the UI to confirm active blocklists
- **qBittorrent:** Set bandwidth limits in the UI to avoid network saturation
- **Minecraft:** Allocate more RAM in `.env` (`MC_MEMORY`) if you have many players
- **Network:** Use 5GHz WiFi or Ethernet for media server connection (reduces buffering)

## ⚠️ Important Security Note: Disable UPnP on Your Router

This setup is designed with a zero open ports philosophy. All external access is securely handled through Tailscale, meaning your server is completely invisible to the public internet.

However, there is one common trap to watch out for:

Services like Plex can automatically use Universal Plug and Play (UPnP) to request your router to open inbound ports without your knowledge. If UPnP is enabled on your router, Plex (and other services) may silently expose your server to the internet, breaking the security model of this setup.

How to verify and fix this:

1. Disable UPnP: Log into your router's administration panel and find the UPnP settings. Uncheck the box to disable it entirely and apply the changes.

2. Check for existing mappings: Before disabling it, review the active UPnP table. You might see something like this:

   | Plex Media Server | 14772 | 32400 | TCP | 192.168.100.65 | Enable |

3. Verify it's gone: After disabling UPnP, refresh the table to ensure all port mappings have been removed.

Why this matters:

By disabling UPnP, you ensure that no service can automatically open your firewall. Combined with zero manual port forwards and Tailscale's secure WireGuard tunnel, your home server remains safely locked down—accessible only to you and your authorized devices.

Note: With UPnP disabled and no open ports, Plex will still work perfectly fine over your local network, and you can securely access it remotely via your Tailscale IP (e.g., http://100.x.x.x:32400).

## License

MIT — do whatever you want with this setup.

## Contributing

This is a personal project, but feel free to fork it. If you find improvements, open a PR!

---

**Questions or issues?** Check the Troubleshooting section or open an issue.
