# Home Server Network Architecture

## Overview

This home server runs Ubuntu Server with Docker Compose and hosts multiple services.

The network has several layers:

* Home router — DHCP and internet gateway
* Pi-hole — DNS and ad blocking
* Docker — application containers
* Nginx Proxy Manager — HTTP/HTTPS reverse proxy
* Main Tailscale — remote access to the home LAN and services
* Minecraft Tailscale — dedicated Tailscale endpoint for Minecraft
* `eggbase.net` — internal service domain
* Home LAN — normal local access

The important architectural feature is that Minecraft has **two Tailscale access paths**:

1. Through the main Tailscale node via the advertised LAN subnet.
2. Directly through its own Tailscale sidecar at `100.72.36.23`.

---

# 0. Quick Look

```text
┌─────────────────────────────────────────────────────────────┐
│                    USER ACCESS PATHS                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  LOCAL LAN          MAIN TAILSCALE      MINECRAFT TAILSCALE │
│  ┌─────────┐        ┌──────────┐        ┌──────────────┐   │
│  │ Browser │        │ Remote   │        │ Remote       │   │
│  │         │        │ Device   │        │ Player       │   │
│  └────┬────┘        └────┬─────┘        └──────┬───────┘   │
│       │                  │                      │           │
│       ▼                  ▼                      ▼           │
│  ┌───────────────────────────────────────────────────────┐  │
│  │               HOME SERVER (Ubuntu)                   │  │
│  │  ┌────────────────────────────────────────────────┐  │  │
│  │  │              DOCKER COMPOSE                   │  │  │
│  │  │  Pi-hole → NPM → Services (Plex, etc.)       │  │  │
│  │  │  Main Tailscale → LAN subnet advertise        │  │  │
│  │  │  Minecraft + Tailscale sidecar (100.72.36.23)│  │  │
│  │  └────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

# 1. High-Level Network

```text
                                      INTERNET
                                         │
                                         │
                              ┌──────────▼──────────┐
                              │     HOME ROUTER     │
                              │                     │
                              │  Internet Gateway   │
                              │  DHCP Server        │
                              │  DNS → Pi-hole      │
                              └──────────┬──────────┘
                                         │
                                         │ HOME LAN
                                         │
              ┌──────────────────────────┼───────────────────────────┐
              │                          │                           │
              │                          │                           │
        LAN DEVICES                UBUNTU SERVER                OTHER DEVICES
        ┌───────────┐              ┌─────────────┐              ┌───────────┐
        │ PC        │              │ Docker Host │              │ TV        │
        │ Laptop    │              │             │              │ Phone     │
        │ Phone     │              │ Home Server │              │ Console   │
        └───────────┘              └─────────────┘              └───────────┘
```

---

# 2. Router and DHCP

The home router provides DHCP to LAN clients.

The router's DHCP configuration tells clients to use the **Ubuntu server's Pi-hole instance as their DNS server**.

```text
                         HOME ROUTER
                              │
                     ┌────────┴────────┐
                     │                 │
                  DHCP              Internet
                     │
                     ▼
              LAN DEVICES
                     │
                     │ DNS server
                     ▼
                  PI-HOLE
```

This means clients automatically receive Pi-hole as their DNS resolver when they connect to the home network.

No manual DNS configuration is required on each device.

---

# 3. Pi-hole DNS

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

The Pi-hole web interface is also exposed directly on:

```text
http://<SERVER_IP>:8081
```

## Local DNS Records

The current local records point service domains to the server's LAN IP:

```text
home.eggbase.net       → SERVER_IP
proxy.eggbase.net      → SERVER_IP
portainer.eggbase.net  → SERVER_IP
pihole.eggbase.net     → SERVER_IP
plex.eggbase.net       → SERVER_IP
torrent.eggbase.net    → SERVER_IP
files.eggbase.net      → SERVER_IP
pdf.eggbase.net        → SERVER_IP
books.eggbase.net      → SERVER_IP
ntfy.eggbase.net       → SERVER_IP
minecraft.eggbase.net  → SERVER_IP
```

The important point is that DNS does **not** directly select the Docker container.

It simply sends the hostname to the server.

Nginx Proxy Manager then decides where the request goes.

---

# 4. DNS Request Flow

For example, when a device requests:

```text
https://plex.eggbase.net
```

the flow is:

```text
DEVICE
  │
  │ DNS query:
  │ "Where is plex.eggbase.net?"
  ▼
HOME ROUTER
  │
  │ DHCP-provided DNS server
  ▼
PI-HOLE
  │
  │ Local DNS record
  │ plex.eggbase.net → SERVER_IP
  ▼
SERVER_IP
```

The browser then connects to:

```text
SERVER_IP:443
```

---

# 5. Nginx Proxy Manager

Nginx Proxy Manager is the reverse proxy.

It listens on:

```text
80  → HTTP
443 → HTTPS
81  → NPM administration
```

The admin interface is available directly at:

```text
http://<SERVER_IP>:81
```

NPM receives HTTPS requests and routes them to the appropriate Docker service.

Conceptually:

```text
                         SERVER_IP:443
                               │
                               ▼
                    ┌─────────────────────┐
                    │ NGINX PROXY MANAGER │
                    └──────────┬──────────┘
                               │
             ┌─────────────────┼─────────────────┐
             │                 │                 │
             ▼                 ▼                 ▼
          Plex             Homepage            ntfy
        :32400               :80                :80
```

---

# 6. HTTPS

The public/internal service domain is:

```text
eggbase.net
```

The service hostnames are under:

```text
*.eggbase.net
```

Nginx Proxy Manager handles the HTTPS certificates and reverse proxying.

The intended architecture is:

```text
https://plex.eggbase.net
        │
        ▼
      HTTPS
        │
        ▼
Nginx Proxy Manager
        │
        ▼
     plex:32400
```

The same pattern can be used for the other services.

---

# 7. Docker Network

Most containers use the Docker network:

```text
home-server-net
```

The application containers communicate with one another using Docker DNS/container names.

For example:

```text
Nginx Proxy Manager
        │
        ├──► homepage:80
        ├──► plex:32400
        ├──► qbittorrent:8080
        ├──► stirlingpdf:8080
        ├──► calibreweb:8083
        └──► ntfy:80
```

Docker container names therefore act as internal service addresses.

---

# 8. Services

## Homepage

Container:

```text
homepage
```

Image:

```text
nginx:alpine
```

Port:

```text
8888:80
```

Direct fallback:

```text
http://<SERVER_IP>:8888
```

It serves the static home dashboard.

It can also be accessed through:

```text
https://home.eggbase.net
```

---

## Nginx Proxy Manager

Container:

```text
nginxproxymanager
```

Ports:

```text
80:80
443:443
81:81
```

Responsibilities:

* Reverse proxy
* HTTPS
* Certificate management
* Domain-based routing

---

## Portainer

Container:

```text
portainer
```

Port:

```text
9000:9000
```

Direct fallback:

```text
http://<SERVER_IP>:9000
```

Domain:

```text
https://portainer.eggbase.net
```

---

## Pi-hole

Container:

```text
pihole
```

Ports:

```text
53:53/tcp
53:53/udp
8081:80
```

Responsibilities:

* DNS
* Ad blocking
* Local DNS records

Direct web interface:

```text
http://<SERVER_IP>:8081/admin
```

---

## Plex

Container:

```text
plex
```

Network mode:

```text
host
```

This is intentional for Plex discovery/DLNA.

Libraries:

```text
/movies
/tv
/downloads
```

Domain:

```text
https://plex.eggbase.net
```

---

## qBittorrent

Container:

```text
qbittorrent
```

Ports:

```text
8080:8080
6881:6881
6881:6881/udp
```

Storage:

```text
/downloads
/other
```

Domain:

```text
https://torrent.eggbase.net
```

---

## Stirling PDF

Container:

```text
stirlingpdf
```

Port:

```text
8082:8080
```

Direct fallback:

```text
http://<SERVER_IP>:8082
```

Domain:

```text
https://pdf.eggbase.net
```

---

## Calibre-Web

Container:

```text
calibreweb
```

Port:

```text
8083:8083
```

Domain:

```text
https://books.eggbase.net
```

Library:

```text
/books
```

---

## ntfy

Container:

```text
ntfy
```

Port:

```text
8084:80
```

Direct fallback:

```text
http://<SERVER_IP>:8084
```

Domain:

```text
https://ntfy.eggbase.net
```

ntfy provides:

* Push notifications
* HTTP publishing
* Web subscriptions
* Application event notifications

---

## Samba

Container:

```text
samba
```

Ports:

```text
139:139
445:445
```

The media directory is exposed over SMB.

Conceptually:

```text
LAN DEVICE
    │
    │ SMB
    ▼
SERVER:445
    │
    ▼
Samba
    │
    ▼
/media
```

---

# 9. Main Tailscale

There are **two Tailscale containers**.

The first is the general-purpose home-server Tailscale instance:

```text
tailscale
```

This is the primary Tailscale node for the home server.

It uses:

```yaml
TS_AUTHKEY: ${TS_AUTHKEY}
TS_STATE_DIR: /var/lib/tailscale
TS_EXTRA_ARGS: --advertise-routes=${LAN_SUBNET} --accept-dns=false
```

It also has:

```yaml
cap_add:
  - NET_ADMIN
  - NET_RAW
```

and:

```text
/dev/net/tun
```

mounted.

---

# 10. Main Tailscale Purpose

The main Tailscale instance provides remote access to the home network.

It advertises:

```text
LAN_SUBNET
```

to the Tailscale network.

Conceptually:

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
      ├── Pi-hole
      ├── Nginx Proxy Manager
      ├── Plex
      ├── qBittorrent
      ├── Samba
      ├── Minecraft
      └── other LAN services
```

This means Minecraft is already reachable through the **main Tailscale path**.

---

# 11. Minecraft Tailscale Sidecar

Minecraft has its own Tailscale sidecar:

```text
minecraft-tailscale
```

It uses:

```yaml
network_mode: "container:minecraft"
```

This is the key part of the architecture.

The Tailscale container shares Minecraft's network namespace.

Conceptually:

```text
┌───────────────────────────────────────┐
│       MINECRAFT NETWORK NAMESPACE     │
│                                       │
│   ┌──────────────┐                    │
│   │  Minecraft   │                    │
│   │              │                    │
│   │ :25565       │                    │
│   │ :19132/udp   │                    │
│   └──────▲───────┘                    │
│          │                            │
│          │ shared network namespace   │
│          │                            │
│   ┌──────┴───────────────┐            │
│   │ minecraft-tailscale  │            │
│   │                       │            │
│   │ tailscale0            │            │
│   │ 100.72.36.23          │            │
│   └───────────────────────┘            │
│                                       │
└───────────────────────────────────────┘
```

The Minecraft Tailscale node currently has:

```text
IPv4:
100.72.36.23

IPv6:
fd7a:115c:a1e0::4b01:24d5
```

---

# 12. Why Minecraft Has Two Tailscale Paths

Minecraft can now be reached in two different ways through Tailscale.

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
MINECRAFT LAN IP
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

The second path does not depend on the LAN subnet route.

---

# 13. Minecraft Access

Minecraft therefore has several possible access paths.

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

### Remote via main Tailscale

```text
REMOTE TAILSCALE DEVICE
    │
    ▼
Main Tailscale
    │
    ▼
LAN subnet
    │
    ▼
Server LAN IP
    │
    ▼
Minecraft
```

### Remote via dedicated Minecraft Tailscale

```text
REMOTE TAILSCALE DEVICE
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

Java:

```text
100.72.36.23:25565
```

Bedrock:

```text
100.72.36.23:19132
```

---

# 14. Complete Network Diagram

```text
                                      INTERNET
                                         │
                                         │
                                         ▼
                              ┌────────────────────┐
                              │    HOME ROUTER     │
                              │                    │
                              │ Internet Gateway   │
                              │ DHCP Server        │
                              │ DNS → Pi-hole      │
                              └─────────┬──────────┘
                                        │
                                        │
                                  HOME LAN
                                        │
             ┌──────────────────────────┼──────────────────────────┐
             │                          │                          │
             ▼                          ▼                          ▼
       LAN CLIENTS               UBUNTU SERVER              OTHER CLIENTS
       ┌───────────┐             ┌────────────────┐           ┌───────────┐
       │ PC        │             │                │           │ TV        │
       │ Laptop    │             │ Docker Host    │           │ Phone     │
       │ Phone     │             │                │           │ Console   │
       └─────┬─────┘             └───────┬────────┘           └───────────┘
             │                           │
             │ DNS                       │
             └──────────────────────────►│
                                         │
                              ┌──────────▼──────────┐
                              │       PI-HOLE       │
                              │                     │
                              │ DNS :53             │
                              │ Ad blocking         │
                              │ Local DNS           │
                              └──────────┬──────────┘
                                         │
                                         │ SERVER_IP
                                         │
                              ┌──────────▼──────────┐
                              │ NGINX PROXY MANAGER │
                              │                     │
                              │ HTTP :80            │
                              │ HTTPS :443          │
                              │ Admin :81           │
                              └──────────┬──────────┘
                                         │
                    ┌────────────────────┼────────────────────┐
                    │                    │                    │
                    ▼                    ▼                    ▼
               Homepage                Plex                 ntfy
               :80                    :32400                 :80
                    │                    │                    │
                    ├── Portainer        ├── qBittorrent      │
                    ├── PDF              ├── Calibre-Web      │
                    └── other services  └── other services   │


                              ┌─────────────────────────────┐
                              │          DOCKER              │
                              │      home-server-net        │
                              │                             │
                              │ homepage                    │
                              │ nginxproxymanager            │
                              │ portainer                    │
                              │ pihole                       │
                              │ qbittorrent                  │
                              │ stirlingpdf                  │
                              │ calibreweb                   │
                              │ ntfy                         │
                              │ samba                        │
                              │                             │
                              └─────────────────────────────┘


        ╔════════════════════════════════════════════════════════════╗
        ║                       TAILSCALE                           ║
        ╚════════════════════════════════════════════════════════════╝
                              │
                ┌─────────────┴─────────────┐
                │                           │
                ▼                           ▼
       ┌─────────────────┐         ┌────────────────────┐
       │  MAIN TAILSCALE │         │ MINECRAFT TAILSCALE│
       │                 │         │                    │
       │ home-server     │         │ minecraft sidecar  │
       │ 100.x.x.x        │         │ 100.72.36.23       │
       │                 │         │                    │
       │ advertise       │         │ shared network     │
       │ LAN_SUBNET      │         │ namespace with     │
       │                 │         │ Minecraft          │
       └────────┬────────┘         └─────────┬──────────┘
                │                            │
                │                            │
                ▼                            ▼
           HOME LAN                    MINECRAFT
                │                            │
                │                     ┌──────┴──────┐
                │                     │             │
                └────────────────────►│ Minecraft   │
                                      │ :25565      │
                                      │ :19132/udp  │
                                      └─────────────┘
```

---

# 15. Domain and Service Routing

The intended service access pattern is:

| Domain                  | Destination              |
| ----------------------- | ------------------------ |
| `home.eggbase.net`      | Homepage                 |
| `proxy.eggbase.net`     | Nginx Proxy Manager      |
| `portainer.eggbase.net` | Portainer                |
| `pihole.eggbase.net`    | Pi-hole                  |
| `plex.eggbase.net`      | Plex                     |
| `torrent.eggbase.net`   | qBittorrent              |
| `files.eggbase.net`     | Samba / file access      |
| `pdf.eggbase.net`       | Stirling PDF             |
| `books.eggbase.net`     | Calibre-Web              |
| `ntfy.eggbase.net`      | ntfy                     |
| `minecraft.eggbase.net` | Minecraft-related access |

Pi-hole resolves these domains to the server IP.

Nginx Proxy Manager then routes HTTP/HTTPS requests to the appropriate service.

---

# 16. Storage

The server uses persistent application data under:

```text
/srv/appdata
```

and media/content under:

```text
/srv/media
```

Typical structure:

```text
/srv/
├── appdata/
│   ├── npm/
│   ├── portainer/
│   ├── pihole/
│   ├── plex/
│   ├── qbittorrent/
│   ├── stirlingpdf/
│   ├── calibreweb/
│   ├── ntfy/
│   └── tailscale/
│
└── media/
    ├── movies/
    ├── tv/
    ├── downloads/
    ├── other/
    └── books/
```

Minecraft has its own persistent storage according to its Minecraft Compose configuration.

The Minecraft Tailscale sidecar stores its Tailscale state separately:

```text
${APPDATA}/tailscale-minecraft
```

---

# 17. Security Boundaries

There are several useful boundaries in this architecture.

## LAN boundary

Normal local devices access services over the home network.

## HTTPS boundary

Nginx Proxy Manager handles encrypted HTTP traffic and certificate management.

## Docker boundary

Services are isolated into containers.

## Main Tailscale boundary

Remote Tailscale devices can access the advertised home LAN.

## Minecraft Tailscale boundary

Minecraft has a dedicated Tailscale identity and IP.

The Minecraft sidecar does not need to expose the entire Docker network through Tailscale.

---

# 18. Key Architectural Principle

The home server effectively uses four layers:

```text
                    ┌─────────────────────┐
                    │       USERS         │
                    └──────────┬──────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │      TAILSCALE      │
                    │ Remote connectivity │
                    └──────────┬──────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │       NETWORK       │
                    │ LAN + Docker        │
                    └──────────┬──────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │       DNS           │
                    │      Pi-hole        │
                    └──────────┬──────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │   REVERSE PROXY     │
                    │ Nginx Proxy Manager │
                    └──────────┬──────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │      SERVICES       │
                    │ Docker containers   │
                    └─────────────────────┘
```

---

# 19. Sidecar Pattern

The Minecraft Tailscale setup establishes a reusable sidecar pattern.

An application can have an infrastructure sidecar that shares its network namespace:

```yaml
services:
  application:
    ...

  application-sidecar:
    image: some-sidecar
    network_mode: "container:application"
    ...
```

For Minecraft:

```yaml
services:
  minecraft-tailscale:
    image: tailscale/tailscale:latest
    container_name: minecraft-tailscale
    network_mode: "container:minecraft"

    environment:
      TS_AUTHKEY: ${TS_AUTHKEY}
      TS_STATE_DIR: /var/lib/tailscale
      TS_USERSPACE: "false"
      TS_EXTRA_ARGS: "--accept-dns=false"

    volumes:
      - ${APPDATA}/tailscale-minecraft:/var/lib/tailscale
      - /dev/net/tun:/dev/net/tun

    cap_add:
      - NET_ADMIN
      - NET_RAW

    restart: unless-stopped
```

This makes the sidecar effectively share the application's network namespace.

---

# 20. Current Tailscale Architecture

There are therefore two Tailscale nodes:

```text
┌───────────────────────────────────────────────┐
│                 TAILSCALE                     │
├───────────────────────────────────────────────┤
│                                               │
│  home-server                                  │
│  ├── General home-server access               │
│  ├── Advertises LAN subnet                    │
│  └── Can reach Minecraft                      │
│                                               │
│  minecraft                                    │
│  ├── Dedicated Minecraft endpoint             │
│  ├── 100.72.36.23                             │
│  ├── Shares Minecraft network namespace       │
│  └── Provides direct Minecraft access         │
│                                               │
└───────────────────────────────────────────────┘
```

---

# 21. Summary

The home server has the following overall flow:

```text
Internet
   │
   ▼
Router
   │
   ├── DHCP
   │     └── DNS → Pi-hole
   │
   └── Home LAN
          │
          ▼
      Ubuntu Server
          │
          ├── Pi-hole
          │      └── Local DNS
          │
          ├── Nginx Proxy Manager
          │      └── HTTPS / reverse proxy
          │
          ├── Docker services
          │      ├── Homepage
          │      ├── Portainer
          │      ├── Plex
          │      ├── qBittorrent
          │      ├── Stirling PDF
          │      ├── Calibre-Web
          │      ├── ntfy
          │      └── Samba
          │
          ├── Main Tailscale
          │      └── LAN subnet access
          │
          └── Minecraft
                 │
                 └── Minecraft Tailscale sidecar
                        └── 100.72.36.23
```

The result is a home-server environment where:

* **Router** handles DHCP and internet access.
* **Pi-hole** handles DNS and ad blocking.
* **`eggbase.net`** provides consistent service hostnames.
* **Nginx Proxy Manager** handles HTTPS and reverse proxying.
* **Docker** runs the applications.
* **Main Tailscale** provides remote access to the home LAN.
* **Minecraft Tailscale** provides a dedicated direct Tailscale endpoint for Minecraft.
* **Minecraft remains reachable through the main Tailscale LAN route as well.**
* **LAN access continues to work normally.**
* **The sidecar pattern can be reused for other applications when dedicated network access is useful.**

## 22. Important Security Consideration: UPnP

This architecture assumes **zero open inbound ports** on the home router. 
All remote access is through Tailscale.

**Critical:** Ensure Universal Plug and Play (UPnP) is **disabled** on your router.
Services like Plex can automatically use UPnP to open firewall ports without your 
knowledge, bypassing the security model.

To verify:
1. Log into your router's admin panel.
2. Find the UPnP settings and disable them.
3. Check for existing mappings (e.g., Plex may have opened a port).
4. After disabling, refresh to confirm all mappings are removed.

With UPnP off and no port forwards, your server is invisible to the public internet.

## 23. Common Architectural Pitfalls

### DNS Propagation
- Pi-hole local records take effect immediately.
- If a service isn't reachable via domain, check Pi-hole's local DNS table first.

### Docker Network Isolation
- Services on `home-server-net` can communicate via container names.
- If a service can't reach another, verify they're on the same Docker network.

### Tailscale Connectivity
- Both Tailscale nodes must be authenticated with valid auth keys.
- The Minecraft sidecar shares the Minecraft container's network—verify both are running.


---
**Document Version:** 1.0  
**Last Updated:** 25 August 2026