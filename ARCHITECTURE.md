# Home Server Architecture

**Document Version:** 2.0
**Last Updated:** 29 August 2026
**How was this generated:** CHAT GPT, blame him

---

# 1. Overview

This home server runs **Ubuntu Server** with Docker Compose and provides a collection of self-hosted services.

The architecture is built around several distinct layers:

* **Home Router** — Internet gateway and DHCP
* **Pi-hole** — DNS resolution, local DNS records, and ad blocking
* **Traefik** — HTTPS reverse proxy and automatic certificate management
* **Docker** — Application isolation and service networking
* **Tailscale** — Remote access without exposing services directly to the Internet
* **GitHub Actions** — Automated deployment
* **Self-hosted GitHub Actions Runner** — Executes deployments directly on the server
* **Uptime Kuma** — Service monitoring
* **AutoKuma** — Automatically creates and manages Uptime Kuma monitors from Docker labels
* **ntfy** — Push notification transport
* **Cloudflare** — DNS provider used by Traefik for ACME DNS-01 certificate challenges
* **`eggbase.net`** — Consistent hostname namespace for home services

The server currently hosts:

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
* Uptime Kuma
* AutoKuma
* Tailscale
* Minecraft
* Minecraft Tailscale sidecar

The architecture intentionally avoids Kubernetes. Docker Compose provides the required service orchestration while remaining relatively simple to understand and maintain.

---

# 2. Architectural Model

The server can be understood as four major planes:

```text
┌────────────────────────────────────────────────────────────┐
│                       CONTROL PLANE                        │
│                                                            │
│ GitHub → GitHub Actions → Self-hosted Runner → Docker      │
│                                                            │
│ Automated deployment and server configuration              │
└──────────────────────────────┬─────────────────────────────┘
                               │
                               ▼
┌────────────────────────────────────────────────────────────┐
│                       SERVICE PLANE                        │
│                                                            │
│ Docker Compose                                             │
│                                                            │
│ Traefik / Pi-hole / Plex / Portainer / qBittorrent / etc. │
└──────────────────────────────┬─────────────────────────────┘
                               │
                               ▼
┌────────────────────────────────────────────────────────────┐
│                        ACCESS PLANE                        │
│                                                            │
│ LAN / DNS / HTTPS / Tailscale / Minecraft Tailscale       │
└──────────────────────────────┬─────────────────────────────┘
                               │
                               ▼
┌────────────────────────────────────────────────────────────┐
│                   OBSERVABILITY PLANE                      │
│                                                            │
│ Uptime Kuma ← AutoKuma ← Docker labels                    │
│       │                                                    │
│       ▼                                                    │
│     ntfy → Push notifications                             │
└────────────────────────────────────────────────────────────┘
```

This separation is useful because deployment, service execution, user access, and monitoring are different concerns.

---

# 3. Quick Architecture

```text
                         INTERNET
                            │
                            │
                     ┌──────▼──────┐
                     │ HOME ROUTER │
                     │             │
                     │ Gateway     │
                     │ DHCP        │
                     └──────┬──────┘
                            │
                         HOME LAN
                            │
          ┌─────────────────┼─────────────────┐
          │                 │                 │
          ▼                 ▼                 ▼
     LAN DEVICES       UBUNTU SERVER      OTHER DEVICES
                           │
                           │
                ┌──────────▼──────────┐
                │       PI-HOLE       │
                │                     │
                │ DNS + Ad Blocking   │
                │ Local DNS Records   │
                └──────────┬──────────┘
                           │
                           │ *.eggbase.net
                           ▼
                ┌──────────────────────┐
                │       TRAEFIK        │
                │                      │
                │ HTTP :80             │
                │ HTTPS :443           │
                │ Cloudflare DNS-01    │
                └──────────┬───────────┘
                           │
             ┌─────────────┼──────────────┐
             │             │              │
             ▼             ▼              ▼
         Homepage      Portainer        ntfy
         Plex          qBittorrent      PDF
         Calibre-Web   etc.
             │
             ▼
        Docker Services


      ┌─────────────────────────────────────────┐
      │             CONTROL PLANE               │
      │                                         │
      │ GitHub → Actions → Self-hosted Runner  │
      │                         │               │
      │                         ▼               │
      │                   Docker Compose        │
      └─────────────────────────────────────────┘


      ┌─────────────────────────────────────────┐
      │              REMOTE ACCESS              │
      │                                         │
      │ Main Tailscale → LAN subnet             │
      │ Minecraft Tailscale → Minecraft only    │
      └─────────────────────────────────────────┘


      ┌─────────────────────────────────────────┐
      │             OBSERVABILITY               │
      │                                         │
      │ Docker labels → AutoKuma → Kuma → ntfy │
      └─────────────────────────────────────────┘
```

---

# 4. Home Router

The home router provides the primary network gateway.

Responsibilities:

* Internet connectivity
* DHCP
* Local LAN connectivity
* Default gateway

The router's DHCP configuration provides clients with the Ubuntu server's Pi-hole instance as their DNS server.

```text
HOME ROUTER
    │
    ├── Internet Gateway
    │
    └── DHCP
          │
          ├── IP address
          ├── Gateway
          └── DNS → Pi-hole
```

No individual device should normally require manual DNS configuration.

---

# 5. Network Access Model

There are three primary ways services can be accessed.

## 5.1 Local LAN

```text
LAN DEVICE
    │
    ▼
HOME LAN
    │
    ▼
SERVER
```

Local devices can resolve `*.eggbase.net` through Pi-hole and connect to the server over the LAN.

---

## 5.2 Main Tailscale

```text
REMOTE DEVICE
      │
      │ Tailscale
      ▼
MAIN TAILSCALE
      │
      │ advertised LAN subnet
      ▼
HOME LAN
      │
      ▼
SERVER / SERVICES
```

The main Tailscale node advertises the home LAN subnet, allowing authorized Tailscale devices to access services as though they were connected to the home network.

---

## 5.3 Minecraft Tailscale

Minecraft has a dedicated Tailscale endpoint.

```text
REMOTE PLAYER
      │
      │ Tailscale
      ▼
MINECRAFT TAILSCALE
      │
      ▼
100.72.36.23
      │
      ▼
MINECRAFT
```

This provides a direct Tailscale path to Minecraft independent of the main LAN subnet route.

---

# 6. DNS Architecture

Pi-hole provides:

* DNS resolution
* Ad blocking
* Local DNS records
* Internal service discovery

Pi-hole listens on:

```text
TCP 53
UDP 53
```

The important architectural distinction is:

```text
DNS
 │
 └── hostname → server LAN IP
```

DNS does **not** decide which Docker container receives the request.

For example:

```text
plex.eggbase.net
        │
        ▼
     Pi-hole
        │
        ▼
    SERVER_IP
```

The browser then connects to the server on HTTPS:

```text
SERVER_IP:443
```

Traefik subsequently determines which service receives the request.

---

# 7. Local DNS Records

The current service namespace is:

```text
home.eggbase.net
traefik.eggbase.net
portainer.eggbase.net
pihole.eggbase.net
plex.eggbase.net
torrent.eggbase.net
files.eggbase.net
pdf.eggbase.net
books.eggbase.net
ntfy.eggbase.net
minecraft.eggbase.net
status.eggbase.net
```

These resolve internally through Pi-hole to the server's LAN IP.

Conceptually:

```text
*.eggbase.net
      │
      ▼
   Pi-hole
      │
      ▼
 SERVER_IP
```

---

# 8. DNS Request Flow

When a device requests:

```text
https://plex.eggbase.net
```

the process is:

```text
DEVICE
  │
  │ DNS query
  ▼
PI-HOLE
  │
  │ local DNS record
  ▼
SERVER_IP
  │
  │ HTTPS :443
  ▼
TRAEFIK
  │
  │ hostname routing
  ▼
PLEX
```

---

# 9. Docker Architecture

Docker provides the primary application isolation layer.

Most application containers use:

```text
home-server-net
```

Docker's internal DNS allows containers on the same network to communicate using service/container names.

For example:

```text
Traefik
   │
   ├── homepage:80
   ├── portainer:9000
   ├── qbittorrent:8080
   ├── stirlingpdf:8080
   ├── calibreweb:8083
   ├── ntfy:80
   └── uptime-kuma:3001
```

This means services do not need to know each other's LAN IP addresses.

---

# 10. Traefik Reverse Proxy

Traefik is the current reverse proxy.

It replaces the previous Nginx Proxy Manager architecture.

Traefik listens on:

```text
80  → HTTP
443 → HTTPS
```

The HTTP entrypoint redirects to HTTPS.

```text
HTTP :80
   │
   ▼
HTTPS :443
```

Traefik discovers Docker services through Docker labels.

For example:

```yaml
labels:
  - traefik.enable=true
  - traefik.http.routers.homepage.rule=Host(`home.${DOMAIN_NAME}`)
  - traefik.http.routers.homepage.entrypoints=websecure
  - traefik.http.routers.homepage.tls.certresolver=cloudflare
  - traefik.http.services.homepage.loadbalancer.server.port=80
```

The hostname determines the router, while the service definition determines the Docker container and port.

---

# 11. HTTPS and Cloudflare DNS-01

Traefik manages Let's Encrypt certificates using the Cloudflare DNS-01 challenge.

The architecture is:

```text
Traefik
   │
   │ ACME request
   ▼
Let's Encrypt
   │
   │ DNS-01 challenge
   ▼
Cloudflare DNS
```

The Cloudflare API token is provided to Traefik using:

```text
CF_DNS_API_TOKEN
```

DNS-01 is important because certificate validation does not require exposing port 80 or 443 publicly.

The home router therefore does not need inbound port forwarding for HTTPS.

Certificates are stored persistently in:

```text
/etc/traefik/acme.json
```

which is backed by the host's Traefik application-data directory.

---

# 12. No Public Inbound Access

The intended security model is:

```text
INTERNET
   │
   │ no inbound port forwarding
   X
HOME ROUTER
```

Remote access is provided through Tailscale rather than direct Internet exposure.

Cloudflare is used for DNS-based certificate validation, not as a requirement for routing Internet traffic into the home network.

---

# 13. Homepage

Container:

```text
homepage
```

Image:

```text
nginx:alpine
```

The container serves a static dashboard.

Files mounted into the container include:

```text
index.html
services.json
```

The dashboard is available through:

```text
https://home.eggbase.net
```

Traefik routes:

```text
home.eggbase.net
        │
        ▼
homepage:80
```

---

# 14. Portainer

Container:

```text
portainer
```

Port:

```text
9000
```

Portainer provides Docker management functionality.

The primary access path is:

```text
https://portainer.eggbase.net
```

Traefik routes:

```text
portainer.eggbase.net
        │
        ▼
portainer:9000
```

Portainer has access to the Docker socket and should therefore be considered a highly privileged service.

---

# 15. Pi-hole

Container:

```text
pihole
```

Responsibilities:

* DNS
* Ad blocking
* Local DNS
* Internal service hostname resolution

Ports:

```text
53:53/tcp
53:53/udp
```

The web interface is routed through Traefik:

```text
https://pihole.eggbase.net
```

Pi-hole is also directly responsible for resolving the internal `eggbase.net` hostnames.

---

# 16. Plex

Container:

```text
plex
```

Plex intentionally uses:

```text
network_mode: host
```

This is used to simplify Plex discovery and DLNA functionality.

Plex therefore differs from most application containers.

Instead of being reached through normal Docker-network service discovery, it is reached through the host network.

Traefik uses a file-provider configuration to route:

```text
plex.eggbase.net
        │
        ▼
SERVER / HOST NETWORK
        │
        ▼
Plex :32400
```

Plex has access to:

```text
/movies
/tv
/downloads
```

---

# 17. qBittorrent

Container:

```text
qbittorrent
```

Web interface:

```text
8080
```

Torrent ports:

```text
6881/tcp
6881/udp
```

Storage:

```text
/downloads
/other
```

The web interface is available through:

```text
https://torrent.eggbase.net
```

Traefik routes:

```text
torrent.eggbase.net
        │
        ▼
qbittorrent:8080
```

---

# 18. Stirling PDF

Container:

```text
stirlingpdf
```

Internal application port:

```text
8080
```

Primary hostname:

```text
https://pdf.eggbase.net
```

Stirling PDF provides functionality such as:

* PDF merging
* PDF splitting
* OCR
* Conversion
* Compression
* Other PDF manipulation

Persistent data includes:

```text
trainingData
config
logs
```

---

# 19. Calibre-Web NextGen

Container:

```text
calibreweb
```

Application port:

```text
8083
```

Primary hostname:

```text
https://books.eggbase.net
```

Library:

```text
/calibre-library
```

Book ingestion:

```text
/cwa-book-ingest
```

The service provides the ebook library and web reader.

Kobo synchronization is supported by the current configuration.

---

# 20. ntfy

Container:

```text
ntfy
```

Internal port:

```text
80
```

Primary hostname:

```text
https://ntfy.eggbase.net
```

ntfy provides:

* Push notifications
* HTTP notification publishing
* Web subscriptions
* Application notifications

The service is also used as the notification transport for Uptime Kuma.

The important architectural relationship is:

```text
Application / Monitoring
        │
        ▼
       ntfy
        │
        ▼
     Phone
```

---

# 21. Samba

Container:

```text
samba
```

Ports:

```text
139:139
445:445
```

Samba exposes the media directory over SMB.

```text
LAN DEVICE
    │
    │ SMB
    ▼
SERVER:445
    │
    ▼
SAMBA
    │
    ▼
/media
```

SMB is not routed through Traefik because Traefik handles HTTP/HTTPS traffic rather than SMB.

---

# 22. Uptime Kuma

Container:

```text
uptime-kuma
```

Internal port:

```text
3001
```

Primary hostname:

```text
https://status.eggbase.net
```

Uptime Kuma provides service monitoring.

It monitors HTTP and DNS endpoints and tracks service availability.

The monitoring architecture is:

```text
                 UPTIME KUMA
                      │
          ┌───────────┼───────────┐
          ▼           ▼           ▼
      Homepage     Traefik     Pi-hole
          │           │           │
          ▼           ▼           ▼
      qBittorrent   Plex       ntfy
          │
          ▼
       etc.
```

---

# 23. AutoKuma

AutoKuma automates Uptime Kuma configuration.

Instead of manually creating every monitor in the Uptime Kuma UI, services define their monitoring configuration using Docker labels.

For example:

```yaml
labels:
  - kuma.homepage.http.name=Homepage
  - kuma.homepage.http.url=https://home.${DOMAIN_NAME}
  - kuma.homepage.http.notification_name_list=["ntfy-uptime"]
```

AutoKuma observes the Docker environment and creates or updates the corresponding Uptime Kuma monitor.

The resulting flow is:

```text
Docker labels
      │
      ▼
   AutoKuma
      │
      ▼
Uptime Kuma monitors
```

This makes monitoring part of the service configuration rather than a separate manual configuration task.

---

# 24. Monitoring Notifications

The current architecture uses a single ntfy notification provider for service monitoring.

The provider is managed by AutoKuma/Uptime Kuma and is named:

```text
ntfy-uptime
```

Service monitors reference it using:

```text
notification_name_list=["ntfy-uptime"]
```

The resulting flow is:

```text
SERVICE
   │
   │ failure
   ▼
Uptime Kuma
   │
   ▼
ntfy
   │
   ▼
PHONE
```

When the service recovers:

```text
SERVICE
   │
   │ recovery
   ▼
Uptime Kuma
   │
   ▼
ntfy
   │
   ▼
PHONE
```

The ntfy service itself is intentionally not configured to depend on its own notification provider. If ntfy is unavailable, it cannot deliver its own notification.

---

# 25. Monitoring Coverage

Current monitored services include:

```text
Homepage
Traefik
Pi-hole DNS
Pi-hole Web
Plex
qBittorrent
Stirling PDF
Calibre-Web
ntfy
Uptime Kuma
```

The monitoring configuration is attached to the containers through Docker labels.

This allows a service's deployment configuration and monitoring configuration to remain together.

---

# 26. Main Tailscale

The primary Tailscale container is:

```text
tailscale
```

Its purpose is general-purpose remote access to the home network.

It advertises:

```text
LAN_SUBNET
```

using:

```text
--advertise-routes=${LAN_SUBNET}
```

DNS integration is disabled inside the container:

```text
--accept-dns=false
```

The node has access to:

```text
/dev/net/tun
```

and requires:

```text
NET_ADMIN
NET_RAW
```

capabilities.

---

# 27. Main Tailscale Routing

The main Tailscale path is:

```text
REMOTE DEVICE
      │
      │ Tailscale
      ▼
HOME-SERVER TAILSCALE NODE
      │
      │ advertised LAN subnet
      ▼
HOME LAN
      │
      ├── Server
      ├── Pi-hole
      ├── Samba
      ├── Minecraft
      └── other LAN devices/services
```

The important property is that the main Tailscale node provides access to the LAN rather than merely exposing one Docker container.

---

# 28. Minecraft

Minecraft runs separately from the main application stack.

Container:

```text
minecraft
```

The Minecraft server exposes:

```text
25565/tcp
19132/udp
```

The standard Minecraft services are:

```text
Java
  :25565

Bedrock
  :19132/udp
```

Minecraft uses its own Docker network:

```text
minecraft-net
```

---

# 29. Minecraft Tailscale Sidecar

Minecraft has a dedicated Tailscale sidecar:

```text
minecraft-tailscale
```

The sidecar uses:

```yaml
network_mode: "container:minecraft"
```

This causes the Tailscale container to share Minecraft's network namespace.

Conceptually:

```text
┌──────────────────────────────────────┐
│       MINECRAFT NETWORK NAMESPACE    │
│                                      │
│  ┌──────────────┐                    │
│  │  Minecraft   │                    │
│  │              │                    │
│  │ :25565       │                    │
│  │ :19132/udp   │                    │
│  └──────────────┘                    │
│                                      │
│  ┌──────────────────────────────┐    │
│  │ minecraft-tailscale          │    │
│  │                              │    │
│  │ tailscale0                   │    │
│  │ 100.72.36.23                 │    │
│  └──────────────────────────────┘    │
│                                      │
└──────────────────────────────────────┘
```

The sidecar therefore gives Minecraft its own Tailscale identity without requiring the entire Docker network to be exposed through that Tailscale node.

---

# 30. Minecraft Tailscale Address

The dedicated Minecraft Tailscale endpoint currently uses:

```text
IPv4:
100.72.36.23

IPv6:
fd7a:115c:a1e0::4b01:24d5
```

Minecraft can therefore be reached directly through:

```text
100.72.36.23:25565
```

for Java Edition, and:

```text
100.72.36.23:19132
```

for Bedrock Edition.

---

# 31. Minecraft Has Two Tailscale Paths

Minecraft intentionally has two independent Tailscale access paths.

## Path A — Main Tailscale

```text
REMOTE DEVICE
      │
      ▼
MAIN TAILSCALE
      │
      ▼
LAN SUBNET ROUTE
      │
      ▼
SERVER LAN IP
      │
      ▼
MINECRAFT
```

## Path B — Dedicated Minecraft Tailscale

```text
REMOTE DEVICE
      │
      ▼
MINECRAFT TAILSCALE
      │
      ▼
100.72.36.23
      │
      ▼
MINECRAFT
```

The second path does not depend on the main LAN subnet route.

This provides redundancy and a dedicated network identity for Minecraft.

---

# 32. Minecraft Access Summary

Minecraft can therefore be accessed through:

### Local LAN

```text
LAN DEVICE
    │
    ▼
SERVER LAN IP
    │
    ▼
Minecraft
```

### Main Tailscale

```text
REMOTE DEVICE
    │
    ▼
Main Tailscale
    │
    ▼
LAN subnet
    │
    ▼
Minecraft
```

### Dedicated Minecraft Tailscale

```text
REMOTE DEVICE
    │
    ▼
Minecraft Tailscale
    │
    ▼
100.72.36.23
    │
    ▼
Minecraft
```

---

# 33. GitHub Actions Deployment

The home server uses a **self-hosted GitHub Actions runner** to automate deployment.

The repository contains the server's Docker Compose configuration and related deployment files.

The deployment flow is:

```text
DEVELOPER
    │
    │ git push
    ▼
GITHUB REPOSITORY
    │
    │ workflow trigger
    ▼
GITHUB ACTIONS
    │
    │ runner selection
    ▼
HOME SERVER
    │
    ▼
SELF-HOSTED RUNNER
    │
    ▼
DOCKER COMPOSE
    │
    ▼
RUNNING SERVICES
```

This allows the home server to deploy changes without requiring a separate deployment machine.

---

# 34. Self-Hosted GitHub Actions Runner

The GitHub Actions runner is installed directly on the Ubuntu host.

It is registered as a self-hosted runner with labels:

```text
self-hosted
Linux
X64
eggbase-net
```

Deployment workflows target it with:

```yaml
runs-on: [self-hosted, Linux, X64, eggbase-net]
```

The custom:

```text
eggbase-net
```

label identifies this particular deployment target.

This is useful if additional self-hosted runners are added in the future.

---

# 35. GitHub Actions Execution Model

The runner is installed on the host rather than inside Docker.

Conceptually:

```text
┌─────────────────────────────────────────┐
│             UBUNTU SERVER               │
│                                         │
│  systemd                                │
│     │                                   │
│     ▼                                   │
│  GitHub Actions Runner                  │
│     │                                   │
│     │ shell commands                    │
│     ▼                                   │
│  Docker CLI                             │
│     │                                   │
│     ▼                                   │
│  Docker Engine                          │
│     │                                   │
│     ▼                                   │
│  Containers                             │
└─────────────────────────────────────────┘
```

The runner therefore does not need to join `home-server-net`.

It operates at the host/control-plane level.

---

# 36. Deployment Workflow

The intended workflow is approximately:

```text
git push
   │
   ▼
GitHub Actions
   │
   ▼
Self-hosted runner
   │
   ▼
Checkout repository
   │
   ▼
Verify working directory
   │
   ▼
Docker Compose
   │
   ├── pull images
   │
   └── recreate/start services
   │
   ▼
Updated home server
```

Diagnostic commands such as:

```bash
pwd
ls -la
```

can be used during deployment to verify that the workflow is operating in the expected GitHub Actions workspace.

This is important because the runner's current working directory is the Actions workspace and should not be assumed to be the permanent server project directory.

---

# 37. Docker Image Pinning

Running services use exact image digests rather than floating tags wherever practical.

For example:

```text
image@sha256:<digest>
```

This prevents an unplanned image update from silently changing the deployed software.

The intended update process is deliberate:

```text
Update desired
      │
      ▼
docker compose pull
      │
      ▼
Inspect new image digest
      │
      ▼
Update Compose configuration
      │
      ▼
Commit
      │
      ▼
GitHub Actions deployment
```

This makes container updates reproducible and auditable.

---

# 38. Deployment and Runtime Separation

The GitHub Actions runner belongs to the control plane.

Docker containers belong to the service plane.

The relationship is:

```text
                 GITHUB
                    │
                    ▼
             GitHub Actions
                    │
                    ▼
          Self-hosted Runner
                    │
                    │ Docker CLI
                    ▼
              Docker Engine
                    │
                    ▼
             Docker Compose
                    │
                    ▼
             Service Containers
```

The runner does not need to be exposed as a network service.

---

# 39. Runner Security Boundary

The self-hosted runner is a highly trusted component.

A runner capable of controlling Docker can effectively control the host's container environment.

Therefore:

```text
Git repository
      │
      ▼
GitHub Actions
      │
      ▼
Self-hosted Runner
      │
      ▼
Docker Engine
```

should be treated as a privileged trust chain.

Changes merged into the deployment branch may result in commands being executed directly on the home server.

The deployment repository should therefore be considered trusted infrastructure code.

---

# 40. Storage Architecture

Persistent application data is stored under:

```text
/srv/appdata
```

Media and user content are stored under:

```text
/srv/media
```

Typical structure:

```text
/srv/
├── appdata/
│   ├── traefik/
│   ├── portainer/
│   ├── pihole/
│   ├── plex/
│   ├── qbittorrent/
│   ├── stirlingpdf/
│   ├── calibreweb/
│   ├── ntfy/
│   ├── uptime-kuma/
│   ├── autokuma/
│   ├── tailscale/
│   └── tailscale-minecraft/
│
└── media/
    ├── movies/
    ├── tv/
    ├── downloads/
    ├── other/
    ├── books/
    └── calibreweb-ingest/
```

Minecraft has its own persistent application directory.

---

# 41. Storage Relationships

Media-consuming applications use shared host directories.

For example:

```text
qBittorrent
    │
    ▼
/downloads
    │
    ├── Plex
    └── other media workflows
```

Plex uses:

```text
/movies
/tv
/downloads
```

Calibre-Web uses:

```text
/books
```

The host filesystem therefore provides persistent storage independently of container lifetimes.

---

# 42. Service Routing Table

| Hostname                | Service                    | Routing                |
| ----------------------- | -------------------------- | ---------------------- |
| `home.eggbase.net`      | Homepage                   | Traefik                |
| `traefik.eggbase.net`   | Traefik Dashboard          | Traefik                |
| `portainer.eggbase.net` | Portainer                  | Traefik                |
| `pihole.eggbase.net`    | Pi-hole                    | Traefik                |
| `plex.eggbase.net`      | Plex                       | Traefik file provider  |
| `torrent.eggbase.net`   | qBittorrent                | Traefik                |
| `pdf.eggbase.net`       | Stirling PDF               | Traefik                |
| `books.eggbase.net`     | Calibre-Web                | Traefik                |
| `ntfy.eggbase.net`      | ntfy                       | Traefik                |
| `status.eggbase.net`    | Uptime Kuma                | Traefik                |
| `files.eggbase.net`     | Samba namespace            | DNS only / SMB         |
| `minecraft.eggbase.net` | Minecraft-related hostname | DNS / service-specific |

---

# 43. Protocol Boundaries

Different services use different protocols.

```text
HTTP / HTTPS
    │
    ▼
Traefik
    │
    ├── Homepage
    ├── Portainer
    ├── Pi-hole
    ├── Plex
    ├── qBittorrent
    ├── Stirling PDF
    ├── Calibre-Web
    ├── ntfy
    └── Uptime Kuma

DNS
 │
 ▼
Pi-hole :53

SMB
 │
 ▼
Samba :445

Minecraft Java
 │
 ▼
Minecraft :25565

Minecraft Bedrock
 │
 ▼
Minecraft :19132/udp
```

Traefik is therefore not a universal proxy for every protocol on the server.

---

# 44. Security Boundaries

The architecture contains several useful boundaries.

## LAN Boundary

Normal local services are accessible from the home LAN.

## Docker Boundary

Application services are isolated into containers.

## Reverse Proxy Boundary

HTTP/HTTPS services pass through Traefik.

## DNS Boundary

Pi-hole controls internal hostname resolution.

## Tailscale Boundary

Remote access requires authenticated Tailscale connectivity.

## Minecraft Tailscale Boundary

Minecraft has a dedicated Tailscale identity separate from the general home-server node.

## Control Plane Boundary

GitHub Actions can execute trusted deployment code through the self-hosted runner.

---

# 45. UPnP Security

The intended network architecture assumes:

```text
ZERO OPEN INBOUND PORTS
```

on the home router.

Universal Plug and Play should therefore be disabled.

UPnP can allow applications to automatically create router port mappings.

This could undermine the intended security model by allowing services to expose themselves to the Internet without an explicit manual port-forward configuration.

The router should therefore be configured with:

```text
UPnP: DISABLED
```

Existing mappings should also be reviewed and removed.

The intended remote-access model is:

```text
Internet
   │
   X
   │
Home Router
   │
   ├── LAN
   │
   └── Tailscale
```

rather than:

```text
Internet
   │
   ▼
Port Forward
   │
   ▼
Home Server
```

---

# 46. Tailscale Security Model

The main Tailscale node provides access to the LAN subnet.

This means an authorized Tailscale client may potentially reach more than just the Docker services.

Tailscale access should therefore be treated as trusted network access rather than merely an application login.

The Minecraft sidecar provides a narrower dedicated endpoint:

```text
Minecraft Tailscale
       │
       ▼
Minecraft network namespace
```

This avoids using the Minecraft endpoint as a general gateway into the home network.

---

# 47. Traefik Security

Traefik's Docker provider uses:

```text
/var/run/docker.sock
```

This is a privileged Docker control interface.

Traefik requires it to discover services and their labels.

Because Docker socket access is highly privileged, Traefik should be treated as trusted infrastructure.

The same consideration applies to:

* Portainer
* AutoKuma
* GitHub Actions runner deployment operations

---

# 48. Secrets

Sensitive configuration is supplied through environment variables and the `.env` configuration.

Examples include:

```text
ACME_EMAIL
CF_DNS_API_TOKEN
TRAEFIK_USER
TRAEFIK_PASSWORD_HASH
PIHOLE_PASSWORD
KUMA_USERNAME
KUMA_PASSWORD
NTFY_UPTIME_KUMA_TOPIC
TS_AUTHKEY
SMB_USER
SMB_PASSWORD
```

Secrets should not be committed directly into the Git repository.

The repository should contain configuration templates and references such as:

```text
${CF_DNS_API_TOKEN}
```

rather than the secret itself.

---

# 49. Disabled Media Automation

The Compose configuration contains optional services for future media automation:

```text
Prowlarr
Sonarr
Radarr
```

They are currently disabled.

The intended architecture would be:

```text
Prowlarr
   │
   ▼
Indexers
   │
   ├── Sonarr → TV
   │
   └── Radarr → Movies
             │
             ▼
         qBittorrent
             │
             ▼
          Downloads
```

These services can be enabled later without changing the fundamental network architecture.

---

# 50. Service Dependency Model

The major logical dependencies are:

```text
                    Cloudflare
                        │
                        ▼
                    Traefik
                        │
                        ▼
                 HTTPS Services


Router
  │
  ▼
Pi-hole
  │
  ▼
*.eggbase.net
  │
  ▼
Traefik
  │
  ▼
Docker Services


GitHub
  │
  ▼
GitHub Actions
  │
  ▼
Self-hosted Runner
  │
  ▼
Docker Compose
  │
  ▼
Docker Services


Docker labels
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
Phone
```

---

# 51. Complete Network Diagram

```text
                                      INTERNET
                                          │
                                          │
                                  ┌───────▼────────┐
                                  │   HOME ROUTER  │
                                  │                │
                                  │ Gateway        │
                                  │ DHCP           │
                                  │ UPnP disabled  │
                                  └───────┬────────┘
                                          │
                                       HOME LAN
                                          │
             ┌────────────────────────────┼──────────────────────────┐
             │                            │                          │
             ▼                            ▼                          ▼
       LAN CLIENTS                UBUNTU HOME SERVER            OTHER DEVICES
             │                            │
             │ DNS                        │
             └───────────────────────────►│
                                          │
                                  ┌───────▼────────┐
                                  │     PI-HOLE     │
                                  │                 │
                                  │ DNS :53         │
                                  │ Ad blocking     │
                                  │ Local DNS       │
                                  └───────┬─────────┘
                                          │
                                          │ SERVER_IP
                                          ▼
                                  ┌─────────────────┐
                                  │     TRAEFIK     │
                                  │                 │
                                  │ HTTP :80        │
                                  │ HTTPS :443      │
                                  │ Docker provider │
                                  │ File provider   │
                                  └───────┬─────────┘
                                          │
             ┌────────────────────────────┼─────────────────────────┐
             │                            │                         │
             ▼                            ▼                         ▼
         Homepage                     Portainer                  ntfy
             │                            │                         │
             ├── qBittorrent              │                         │
             ├── Stirling PDF             │                         │
             ├── Calibre-Web              │                         │
             ├── Pi-hole                  │                         │
             ├── Uptime Kuma              │                         │
             └── other services           │                         │
                                          │                         │
                                          └─────────────────────────┘


                    ┌───────────────────────────────────┐
                    │           DOCKER HOST              │
                    │                                   │
                    │       home-server-net             │
                    │                                   │
                    │ homepage                          │
                    │ traefik                           │
                    │ portainer                         │
                    │ pihole                            │
                    │ qbittorrent                       │
                    │ stirlingpdf                       │
                    │ calibreweb                        │
                    │ ntfy                              │
                    │ uptime-kuma                       │
                    │ autokuma                           │
                    │ samba                             │
                    │                                   │
                    └───────────────────────────────────┘


              ┌─────────────────────────────────────────────┐
              │                OBSERVABILITY                │
              │                                             │
              │ Docker labels                               │
              │      │                                      │
              │      ▼                                      │
              │   AutoKuma                                  │
              │      │                                      │
              │      ▼                                      │
              │ Uptime Kuma                                 │
              │      │                                      │
              │      ▼                                      │
              │    ntfy                                     │
              │      │                                      │
              │      ▼                                      │
              │    PHONE                                    │
              └─────────────────────────────────────────────┘


              ┌─────────────────────────────────────────────┐
              │                 CONTROL PLANE               │
              │                                             │
              │ Developer                                   │
              │     │                                       │
              │     ▼                                       │
              │ GitHub Repository                           │
              │     │                                       │
              │     ▼                                       │
              │ GitHub Actions                              │
              │     │                                       │
              │     ▼                                       │
              │ Self-hosted Runner                          │
              │     │                                       │
              │     ▼                                       │
              │ Docker Compose                              │
              │     │                                       │
              │     ▼                                       │
              │ Docker Engine                               │
              └─────────────────────────────────────────────┘


              ┌─────────────────────────────────────────────┐
              │                  TAILSCALE                  │
              │                                             │
              │  Main Tailscale                             │
              │       │                                     │
              │       └── advertise LAN_SUBNET             │
              │                    │                        │
              │                    ▼                        │
              │                 HOME LAN                    │
              │                                             │
              │  Minecraft Tailscale                        │
              │       │                                     │
              │       └── 100.72.36.23                      │
              │                    │                        │
              │                    ▼                        │
              │                Minecraft                    │
              └─────────────────────────────────────────────┘
```

---

# 52. Complete Service Architecture

```text
Ubuntu Server
│
├── Docker Engine
│   │
│   ├── home-server-net
│   │   │
│   │   ├── homepage
│   │   ├── traefik
│   │   ├── portainer
│   │   ├── pihole
│   │   ├── qbittorrent
│   │   ├── stirlingpdf
│   │   ├── calibreweb
│   │   ├── ntfy
│   │   ├── uptime-kuma
│   │   ├── autokuma
│   │   └── samba
│   │
│   └── minecraft-net
│       │
│       └── minecraft
│
├── Main Tailscale
│   └── LAN subnet routing
│
├── Minecraft Tailscale
│   └── shared network namespace with Minecraft
│
└── GitHub Actions Runner
    └── Docker Compose deployment
```

---

# 53. Current Tailscale Architecture

There are two Tailscale nodes.

```text
┌──────────────────────────────────────────────┐
│                  TAILSCALE                   │
├──────────────────────────────────────────────┤
│                                              │
│ home-server                                  │
│ ├── General home-server access               │
│ ├── Advertises LAN subnet                    │
│ └── Can reach Minecraft                      │
│                                              │
│ minecraft                                    │
│ ├── Dedicated Minecraft endpoint             │
│ ├── 100.72.36.23                              │
│ ├── Shares Minecraft network namespace       │
│ └── Provides direct Minecraft access         │
│                                              │
└──────────────────────────────────────────────┘
```

---

# 54. Operational Model

The server can be administered manually or automatically.

## Manual

```text
SSH / Terminal
      │
      ▼
Docker CLI
      │
      ▼
Docker Compose
```

## Automated

```text
Git push
   │
   ▼
GitHub Actions
   │
   ▼
Self-hosted Runner
   │
   ▼
Docker Compose
```

Both ultimately operate on the same Docker Engine.

---

# 55. Failure Domains

The architecture contains several relatively independent failure domains.

## Pi-hole failure

DNS resolution for internal service hostnames may fail.

Direct IP access may still work where supported.

## Traefik failure

HTTPS hostname-based access fails, but individual services may still be running.

## Docker failure

Most application services become unavailable.

## Main Tailscale failure

Remote LAN access through the main Tailscale path fails.

The dedicated Minecraft Tailscale endpoint can remain available.

## Minecraft Tailscale failure

The dedicated Minecraft endpoint fails, but Minecraft can remain accessible through:

* Local LAN
* Main Tailscale LAN routing

## ntfy failure

Monitoring can continue, but push notifications cannot be delivered.

## Uptime Kuma failure

Service monitoring stops, but the monitored services themselves can continue running.

## GitHub Actions failure

Automatic deployment stops, but the currently running services continue operating.

This is an important property of the deployment architecture: **GitHub is not required for the server to continue serving its existing workloads.**

---

# 56. Architectural Principles

The home server follows several deliberate principles.

### Keep infrastructure simple

Docker Compose is used instead of Kubernetes.

### Separate access from service execution

Tailscale provides remote connectivity while Docker runs applications.

### Use DNS for names, not service discovery

Pi-hole maps service hostnames to the server.

Traefik performs HTTP service routing.

### Keep public exposure at zero

No router port forwarding is required.

### Use DNS-01 for certificates

Let's Encrypt certificates can be issued without exposing HTTP challenge endpoints.

### Treat infrastructure as code

Docker Compose and related configuration live in Git.

### Automate deployment

GitHub Actions deploys through a self-hosted runner.

### Keep monitoring declarative

Docker labels define Uptime Kuma monitors through AutoKuma.

### Keep notifications independent

ntfy acts as the notification transport for monitoring.

### Give special workloads dedicated networking when useful

Minecraft uses a dedicated Tailscale sidecar without exposing the general Docker network.

### Pin production images

Exact image digests are used to avoid unexpected image changes.

---

# 57. Final Architecture Summary

The complete architecture is:

```text
                         INTERNET
                            │
                            ▼
                     ┌────────────┐
                     │   ROUTER   │
                     │ DHCP       │
                     │ Gateway    │
                     │ UPnP OFF   │
                     └─────┬──────┘
                           │
                        HOME LAN
                           │
             ┌─────────────┼─────────────┐
             │             │             │
             ▼             ▼             ▼
           Clients      Ubuntu Server   Clients
                           │
              ┌────────────┼─────────────┐
              │            │             │
              ▼            ▼             ▼
           Pi-hole      Tailscale      GitHub
              │            │             │
              │            │             ▼
              │            │       GitHub Actions
              │            │             │
              │            │             ▼
              │            │       Self-hosted Runner
              │            │             │
              │            │             ▼
              │            │       Docker Compose
              │            │             │
              │            │             ▼
              │            │       Docker Engine
              │            │             │
              │            │             ▼
              │            │       Home Services
              │            │
              │            ├── LAN subnet
              │            │
              │            └── Remote access
              │
              ▼
        *.eggbase.net
              │
              ▼
           Traefik
              │
      ┌───────┼────────┬──────────┐
      ▼       ▼        ▼          ▼
   Homepage  Plex   Portainer    ntfy
      │
      ├── qBittorrent
      ├── Stirling PDF
      ├── Calibre-Web
      ├── Pi-hole
      └── Uptime Kuma
                             
Docker labels
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
    PHONE


Minecraft
    │
    ├── Local LAN
    │
    ├── Main Tailscale
    │
    └── Minecraft Tailscale
             │
             ▼
        100.72.36.23
```

The resulting system is a self-contained home infrastructure platform with:

* **Router** handling DHCP and Internet access
* **Pi-hole** handling DNS and ad blocking
* **`eggbase.net`** providing consistent internal service names
* **Traefik** handling HTTPS and reverse proxying
* **Cloudflare DNS-01** handling certificate validation
* **Docker Compose** running the applications
* **GitHub Actions** providing automated deployment
* **Self-hosted runner** executing deployment directly on the Ubuntu host
* **Tailscale** providing remote LAN access
* **Minecraft Tailscale** providing a dedicated Minecraft endpoint
* **Uptime Kuma** monitoring service availability
* **AutoKuma** turning Docker labels into monitoring configuration
* **ntfy** delivering push notifications
* **Samba** providing LAN file access
* **Pinned container images** providing controlled deployments
* **Zero intentional inbound router ports** maintaining the remote-access security model

The architecture therefore separates **deployment, networking, service execution, remote access, and observability** while keeping all of the infrastructure manageable through Docker Compose and Git.
