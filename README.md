# Home Server Stack

A reproducible, self-hosted home-server infrastructure project built around Docker Compose, Traefik, Pi-hole, Tailscale, Uptime Kuma, and GitHub Actions.

The project provides a single, version-controlled configuration for running a personal media and utility server with automatic HTTPS, local DNS, remote access, service monitoring, push notifications, and automated deployment.

The goal is deliberately simple:

> **Keep the infrastructure reproducible, observable, remotely accessible, and easy to redeploy without introducing unnecessary orchestration complexity.**

---

## But really, why does this exist?

I want a home server, and when this **bastard** eventually explodes, I want to be able to rebuild it.

---

# Architecture

The server is split into three Compose projects:

```text
home-server/

│
├── docker-compose.yml
│   └── Main home-server stack
│
├── subsetup/
│   ├── minecraft/
│   │   └── Minecraft server
│   │
│   └── minecraft-tailscale/
│       └── Tailscale sidecar for Minecraft
│
├── scripts/
│   ├── setup.sh
│   ├── generate-homepage.sh
│   └── ...
│
├── index.html
├── services.json
└── .github/
    └── workflows/
        └── ...
```

## Main stack

The main Compose project contains:

* Homepage
* Traefik
* Portainer
* Pi-hole
* Plex
* qBittorrent
* Stirling PDF
* Calibre-Web NextGen
* ntfy
* Samba
* Tailscale
* Uptime Kuma
* AutoKuma

## Minecraft stack

Minecraft is deliberately separated from the main stack.

It runs independently with:

* Minecraft Java server
* Geyser
* Floodgate

A separate Tailscale sidecar shares Minecraft's network namespace, allowing Minecraft to have its own Tailnet identity without coupling it to the main server's Tailscale container.

---

# Features

## Infrastructure as Code

The server configuration lives in Git and is intended to be reproducible.

Configuration includes:

* Docker Compose definitions
* Environment templates
* Service configuration
* Reverse-proxy configuration
* DNS configuration
* Monitoring configuration
* Deployment workflows
* Setup scripts

The objective is that the server's infrastructure is defined by the repository rather than by undocumented manual configuration.

---

## Exact image pinning

Running container images are pinned to their exact image digests:

```yaml
image: some/image@sha256:...
```

This prevents a `latest` tag from silently changing the software being deployed.

Updates are therefore intentional:

```bash
docker compose pull
docker compose up -d
```

After verifying the new image, the digest can be committed to Git.

This gives the deployment a deterministic relationship between the Git commit and the container image being executed.

The workflow used to obtain new digests is as follows:

```bash
# 1. See what's new upstream, pull it out-of-band
docker pull lscr.io/linuxserver/plex:latest

# 2. Get the digest
docker inspect --format '{{index .RepoDigests 0}}' lscr.io/linuxserver/plex:latest
# lscr.io/linuxserver/plex@sha256:f6c58cb2f5e4...

# 3. Update the compose pin, then with the new digest hash
```

---

# Reverse Proxy and HTTPS

## Traefik

[Traefik](https://traefik.io/) is the reverse proxy for the server.

It handles:

* HTTP → HTTPS redirection
* HTTPS termination
* Docker service discovery
* Routing based on hostnames
* Let's Encrypt certificates
* Cloudflare DNS-01 challenges

Services expose their routing configuration directly through Docker labels.

For example:

```yaml
labels:
  - traefik.enable=true
  - traefik.http.routers.stirlingpdf.rule=Host(`pdf.${DOMAIN_NAME}`)
  - traefik.http.routers.stirlingpdf.entrypoints=websecure
  - traefik.http.routers.stirlingpdf.tls.certresolver=cloudflare
  - traefik.http.services.stirlingpdf.loadbalancer.server.port=8080
```

This means adding a new web service generally only requires:

1. Running the container.
2. Adding its Traefik labels.
3. Adding its local DNS record.

There is no separate reverse-proxy configuration UI.

---

## Cloudflare DNS-01

Traefik obtains Let's Encrypt certificates using the Cloudflare DNS-01 challenge.

The Cloudflare API token is provided through:

```text
CF_DNS_API_TOKEN
```

The token should be restricted to the required DNS permissions for the relevant zone.

The DNS-01 challenge means the server does **not** need to expose an HTTP challenge endpoint to the internet.

Cloudflare is being used for DNS and ACME DNS-01 validation. Application traffic itself does not need to pass through Cloudflare's proxy.

---

# Local DNS

Pi-hole provides local DNS for the services.

For example:

```text
home.example
traefik.example
portainer.example
pihole.example
plex.example
torrent.example
pdf.example
books.example
ntfy.example
minecraft.example
status.example
```

The records are generated directly through Pi-hole's configuration:

```yaml
FTLCONF_dns_hosts: |
  ${SERVER_IP} home.${DOMAIN_NAME}
  ${SERVER_IP} traefik.${DOMAIN_NAME}
  ${SERVER_IP} portainer.${DOMAIN_NAME}
  ...
```

No manually maintained `custom.list` is required.

Clients on the LAN should use the server's IP address as their DNS server.

---

# Remote Access

## Tailscale

[Tailscale](https://tailscale.com/) provides remote access to the home network.

The main Tailscale container advertises the LAN subnet:

```text
--advertise-routes=${LAN_SUBNET}
```

This allows authorized Tailnet devices to reach services on the home network without opening application ports directly to the public internet.

The server therefore does not need conventional port forwarding for normal remote administration and service access.

---

## Minecraft Tailscale

Minecraft uses a separate Tailscale container:

```yaml
network_mode: "container:minecraft"
```

The Tailscale sidecar therefore shares Minecraft's network namespace.

This gives the Minecraft server an independent Tailnet presence while keeping the Minecraft deployment separate from the main home-server Tailscale instance.

Minecraft supports:

* Java Edition
* Bedrock Edition through Geyser
* Floodgate authentication

The Geyser and Floodgate versions are pinned explicitly in the Compose configuration.

---

# Monitoring

## Uptime Kuma

[Uptime Kuma](https://github.com/louislam/uptime-kuma) provides service monitoring.

The dashboard is available at:

```text
https://status.${DOMAIN_NAME}
```

Monitors cover the important services and test their actual endpoints rather than merely checking whether a Docker container exists.

Examples include:

* Homepage
* Traefik
* Portainer
* Pi-hole DNS
* Pi-hole web UI
* Plex
* qBittorrent
* Stirling PDF
* Calibre-Web
* ntfy
* Uptime Kuma itself

---

## AutoKuma

[AutoKuma](https://github.com/BigBoot/AutoKuma) automatically creates and manages Uptime Kuma monitors from Docker labels.

A service can therefore declare its own monitoring configuration:

```yaml
labels:
  - kuma.pdf.http.name=Stirling PDF
  - kuma.pdf.http.url=https://pdf.${DOMAIN_NAME}
  - kuma.pdf.http.notification_name_list=["ntfy-uptime"]
```

This keeps monitoring configuration close to the service it belongs to.

Adding a service does not require manually creating a corresponding monitor in Uptime Kuma.

---

# Notifications

## ntfy

[ntfy](https://ntfy.sh/) provides push notifications.

Uptime Kuma uses ntfy as its notification backend.

The architecture is:

```text
Service
   │
   ▼
AutoKuma
   │
   ▼
Uptime Kuma
   │
   ▼
ntfy
   │
   ▼
Phone / Desktop
```

If a monitored service goes down, Uptime Kuma can push a notification to the configured ntfy topic.

The ntfy service itself intentionally does not depend on the ntfy notification provider. If ntfy goes down, it cannot be expected to notify itself.

---

# Automated Deployment

## Repository & Deployment Model

This project uses two Git repositories.

### Public repository

The public repository contains:

* Home-server configuration
* Documentation
* Architecture
* Deployment tooling
* Reproducible infrastructure definitions

It serves as the public, reproducible representation of the infrastructure and as a technical reference for the project.

### Private repository

The private repository contains the operational copy used for automated deployment.

The separation is intentional.

The server uses a **self-hosted GitHub Actions runner installed directly on the home server**. Because the runner has access to the server and its Docker environment, it is a high-trust execution environment.

Keeping the deployment workflow in the private repository prevents the public repository from directly exposing GitHub Actions workflows capable of executing commands on the home server.

The resulting model is:

```text
Public Repository
    │
    │  Infrastructure, configuration & documentation
    │
    ▼
Private Repository
    │
    │  Trusted deployment workflow
    ▼
GitHub Actions
    │
    ▼
Self-Hosted Runner
    │
    ▼
Home Server
    │
    ▼
Docker Compose
```

This creates a deliberate separation between **publicly documented infrastructure** and the **private automation that has authority to operate it**.

The public repository can therefore remain open as a technical reference and portfolio for the project, while the private repository acts as the trusted deployment control plane.

This is done simply by having 2 origins on the local working copy. Hence when changes are pushed, they go to both repositories. 

---

## GitHub Actions

Deployment is automated through GitHub Actions.

The self-hosted runner runs directly on the home server and is assigned a dedicated label:

```text
eggbase-net
```

The deployment workflow targets:

```yaml
runs-on: [self-hosted, Linux, X64, eggbase-net]
```

This provides an explicit connection between:

```text
Private GitHub repository
        │
        ▼
GitHub Actions
        │
        ▼
eggbase-net runner
        │
        ▼
Home server
        │
        ▼
Docker Compose
        │
        ▼
Updated services
```

The runner can therefore apply infrastructure changes without exposing Docker's management interface to the public internet.

The server is simultaneously:

* the production environment
* the deployment target
* the GitHub Actions runner

This is intentional. The project is a single-node home infrastructure environment, so the deployment system is kept deliberately simple rather than introducing an external orchestration platform.

A typical deployment consists of:

```bash
git checkout
docker compose pull
docker compose up -d
```

The exact commands are defined by the workflow.

This means infrastructure changes can follow the normal Git workflow:

```text
Edit
  ↓
Commit
  ↓
Push
  ↓
GitHub Actions
  ↓
Self-hosted runner
  ↓
Home server
  ↓
Compose deployment
```

---

## Runner troubleshooting

Check the runner service:

```bash
sudo systemctl status "$(cat .service)"
```

View recent logs:

```bash
sudo journalctl -u "$(cat .service)" -n 50 --no-pager
```

Check that the runner is online in GitHub and that its labels match the workflow's `runs-on` configuration.

If a workflow remains queued, verify:

1. The runner service is running.
2. The runner is online in GitHub.
3. The runner has the expected labels.
4. The workflow requests those exact labels.
5. The runner has permission to access Docker.
6. The repository checkout directory is correct.

---

# Services

| Service          | Purpose                      | Address                            |
| ---------------- | ---------------------------- | ---------------------------------- |
| **Homepage**     | Static dashboard             | `https://home.${DOMAIN_NAME}`      |
| **Traefik**      | Reverse proxy + HTTPS        | `https://traefik.${DOMAIN_NAME}`   |
| **Portainer**    | Docker management            | `https://portainer.${DOMAIN_NAME}` |
| **Pi-hole**      | DNS + ad blocking            | `https://pihole.${DOMAIN_NAME}`    |
| **Plex**         | Media streaming              | `https://plex.${DOMAIN_NAME}`      |
| **qBittorrent**  | Torrent client               | `https://torrent.${DOMAIN_NAME}`   |
| **Stirling PDF** | PDF manipulation/OCR         | `https://pdf.${DOMAIN_NAME}`       |
| **Calibre-Web**  | Ebook library/reader         | `https://books.${DOMAIN_NAME}`     |
| **ntfy**         | Push notifications           | `https://ntfy.${DOMAIN_NAME}`      |
| **Samba**        | LAN file sharing             | `\\<server-ip>\media`              |
| **Tailscale**    | Remote network access        | Tailnet                            |
| **Uptime Kuma**  | Monitoring                   | `https://status.${DOMAIN_NAME}`    |
| **AutoKuma**     | Automatic monitor management | Internal                           |
| **Minecraft**    | Java + Bedrock server        | `25565` / `19132/udp`              |

---

# Optional Services

The main Compose file also contains disabled definitions for:

* Sonarr
* Radarr
* Prowlarr

These are intentionally commented out.

They can be enabled later if automated media acquisition is wanted.

When enabling them, the corresponding:

* appdata directories
* Pi-hole DNS records
* Traefik labels
* monitoring configuration

should also be added.

---

# Resource Limits

Containers have explicit CPU and memory limits where appropriate.

This prevents a single workload from consuming all available resources on the server.

For example:

| Service      | CPU limit | Memory limit |
| ------------ | --------: | -----------: |
| Homepage     |      0.25 |          64M |
| Traefik      |      0.50 |         256M |
| Portainer    |      0.50 |         256M |
| Pi-hole      |      0.50 |         200M |
| Plex         |      1.50 |           2G |
| qBittorrent  |      1.00 |           1G |
| Stirling PDF |      0.75 |           2G |
| Calibre-Web  |      0.75 |         512M |
| ntfy         |      0.25 |         128M |
| Tailscale    |      0.25 |         128M |
| Uptime Kuma  |      0.75 |         384M |
| AutoKuma     |      0.50 |         256M |

Stirling PDF receives a relatively large memory allocation because it runs several heavyweight document-processing components, including Java, LibreOffice, OCR tooling, ImageMagick, Ghostscript, and Calibre.

Its JVM also detects the container's memory limit and dynamically configures its heap:

```text
InitialRAM = 25%

MaxRAM = 60%

MaxMeta = 128M
```

---

# Storage

The default directory layout is:

```text
/srv/

├── appdata/
│   ├── autokuma/
│   ├── calibreweb/
│   ├── minecraft/
│   ├── ntfy/
│   ├── pihole/
│   ├── plex/
│   ├── portainer/
│   ├── qbittorrent/
│   ├── stirlingpdf/
│   ├── tailscale/
│   ├── tailscale-minecraft/
│   ├── traefik/
│   └── uptime-kuma/
│
└── media/
    ├── books/
    ├── calibreweb-ingest/
    ├── downloads/
    ├── movies/
    ├── other/
    └── tv/
```

Application configuration is kept separate from media.

This makes it possible to back up configuration without necessarily backing up large media collections.

---

# Setup

## Prerequisites

The server requires:

* Linux
* Docker
* Docker Compose
* Git
* A static DHCP lease
* A Cloudflare-managed domain
* A Tailscale account
* Sufficient storage for media
* A GitHub repository for the infrastructure configuration

The setup has been developed and tested primarily on Ubuntu.

---

# Initial Setup

Clone the repository:

```bash
git clone https://github.com/zxeenu/home-server.git

cd home-server
```

Run the setup script:

```bash
chmod +x scripts/setup.sh

sudo ./scripts/setup.sh
```

The setup script:

* Creates the application-data directories.
* Creates the media directories.
* Creates `.env` from `.env.example` when necessary.
* Detects the server's LAN IP.
* Sets appropriate ownership.

---

# Environment Configuration

Edit:

```bash
nano .env
```

Important variables include:

```bash
SERVER_IP=192.168.1.50
DOMAIN_NAME=example.com
TZ=Indian/Maldives
PUID=1000
PGID=1000

PIHOLE_PASSWORD=...
SMB_USER=media
SMB_PASSWORD=...

TS_AUTHKEY=...

ACME_EMAIL=...
CF_DNS_API_TOKEN=...

TRAEFIK_USER=admin
TRAEFIK_PASSWORD_HASH=...

KUMA_USERNAME=...
KUMA_PASSWORD=...

NTFY_UPTIME_KUMA_TOPIC=...
```

Secrets must never be committed to Git.

---

# Starting the Main Stack

```bash
docker compose up -d
```

Check the services:

```bash
docker compose ps
```

View logs:

```bash
docker compose logs -f <service>
```

---

# Starting Minecraft

Minecraft is deployed separately:

```bash
cd subsetup/minecraft

docker compose up -d
```

The Minecraft Tailscale sidecar is deployed from:

```bash
cd subsetup/minecraft-tailscale

docker compose up -d
```

---

# Traefik File Provider

Most services are discovered automatically through Docker labels.

Plex is an exception because it uses:

```yaml
network_mode: host
```

This is useful for Plex discovery and DLNA but means Docker-network service discovery cannot be used in the normal way.

Plex routing is therefore configured through Traefik's file provider:

```text
/srv/appdata/traefik/dynamic/plex.yml
```

This is an intentional exception rather than a second reverse-proxy system.

---

# Plex

Plex uses host networking:

```yaml
network_mode: host
```

This simplifies:

* LAN discovery
* DLNA
* Plex client compatibility

The media directories are mounted directly:

```text
movies
tv
downloads
```

Intel Quick Sync hardware transcoding can be enabled by exposing:

```yaml
devices:
  - /dev/dri:/dev/dri
```

---

# qBittorrent

qBittorrent separates completed downloads from temporary/other files:

```text
/downloads
/other
```

The completed downloads directory is also accessible to Plex.

---

# Stirling PDF

Stirling PDF provides:

* PDF merging
* PDF splitting
* OCR
* Compression
* Conversion
* Image manipulation
* Office document conversion
* Ebook conversion

The container includes:

* Java
* LibreOffice
* OCRmyPDF
* Tesseract
* Ghostscript
* ImageMagick
* qpdf
* Calibre

Because of the combined workload, Stirling PDF has a **2G container memory limit**.

---

# Calibre-Web

Calibre-Web NextGen is used for the ebook library and browser-based reading.

The library is mounted at:

```text
/calibre-library
```

An ingest directory is also provided:

```text
/cwa-book-ingest
```

The deployment uses a pinned image digest to keep the running version reproducible.

---

# Samba

The media directory is exposed over SMB.

Windows:

```text
\\<server-ip>\media
```

Linux:

```bash
mount -t cifs //<server-ip>/media /mnt/media \
  -o username=<SMB_USER>,password=<SMB_PASSWORD>
```

Samba is intended primarily for LAN access.

---

# Security Model

The server follows a **minimal exposed-port philosophy**.

Public-facing application ports should not be forwarded through the router.

Normal access is provided through:

```text
LAN
 │
 ├── Pi-hole DNS
 │
 └── Traefik HTTPS

Remote device
 │
 └── Tailscale
      │
      └── Home network
```

Tailscale provides the remote network path, while Traefik provides consistent HTTPS routing.

---

## Disable UPnP

UPnP should be disabled on the router.

Services such as Plex can otherwise request automatic port mappings.

Check the router's existing port mappings before disabling UPnP and remove any mappings that should not exist.

The intended security model is:

```text
No manual application port forwarding
+
No UPnP
+
Tailscale for remote access
+
Traefik for internal HTTPS
```

---

# Backups

Application configuration can be backed up separately from media.

For example:

```bash
tar -czf appdata-backup-$(date +%Y%m%d).tar.gz /srv/appdata
```

Restore:

```bash
tar -xzf appdata-backup-*.tar.gz -C /
```

The Git repository itself contains the infrastructure definition, while `/srv/appdata` contains service state and databases.

Both are therefore important for disaster recovery.

---

# Maintenance

Check running containers:

```bash
docker compose ps
```

Check resource usage:

```bash
docker stats
```

Check disk usage:

```bash
df -h
```

Check application-data usage:

```bash
sudo du -h --max-depth=1 /srv | sort -h
```

Pull updated images:

```bash
docker compose pull
```

Apply them:

```bash
docker compose up -d
```

Because images are pinned by digest, updating the repository's Compose configuration is an intentional operation.

---

# Project Philosophy

This project intentionally uses Docker Compose rather than Kubernetes.

The server is a single-node home infrastructure environment, so the objective is not to reproduce a cloud orchestration platform.

Instead, the stack emphasizes:

* **Simple deployment**
* **Reproducibility**
* **Explicit configuration**
* **Pinned software versions**
* **Automatic HTTPS**
* **Private remote access**
* **Service monitoring**
* **Automated notifications**
* **Git-based change management**
* **Automated deployment**

The result is a relatively small infrastructure stack that still provides many of the operational benefits normally associated with larger deployments.

---

# TODO

* Setup secrets management
* Improve disaster-recovery automation
* Test full server restoration from backup

---

# License

MIT — do whatever you want with it.

---

# Contributing

This is primarily a personal infrastructure project, but improvements and suggestions are welcome.

If you fork the repository, replace the environment-specific values in `.env.example` and adapt the service definitions to your own hardware and network.

---

# Repository

GitHub:

```text
https://github.com/zxeenu/home-server
```

The public repository is the source of truth for the publicly documented infrastructure configuration.

The private operational repository is used for trusted automated deployment through the self-hosted GitHub Actions runner.

---

**How was this generated:** CHAT GPT, blame him.
