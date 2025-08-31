# Streaming Service

A self-hosted media streaming and management solution using Docker containers for automated torrent downloading, VPN protection, and media organization.

## Overview

This project provides a complete streaming infrastructure that automatically downloads, organizes, and serves media content through a secure VPN connection. The setup includes torrent management, automated media organization, and a clean web interface for streaming.

## Architecture

```
┌─────────────┐    ┌──────────────┐    ┌───────────────┐
│   Gluetun   │────│ Transmission │────│   FlexGet     │
│   (VPN)     │    │  (Torrents)  │    │ (Organizer)   │
└─────────────┘    └──────────────┘    └───────────────┘
       │                   │                    │
       └───────────────────┼────────────────────┘
                           │
              ┌──────────────────────┐
              │   Media Library      │
              │ (Movies/TV Shows)    │
              └──────────────────────┘
                           │
              ┌──────────────────────┐
              │  Streaming Service   │
              │    (Web Player)      │
              └──────────────────────┘
```

## Components

### Core Services

- **[Gluetun](https://github.com/qdm12/gluetun)** - VPN client in a Docker container
- **[Transmission](https://transmissionbt.com/)** - BitTorrent client with web interface
- **[FlexGet](https://flexget.com/)** - Automation tool for media organization

### Features

- **Secure Downloads**: All torrent traffic routed through VPN
- **Automated Organization**: FlexGet automatically renames and organizes media
- **Web Interface**: Browser-based access to torrent management
- **Media Streaming**: Direct streaming from organized media library

## Prerequisites

- Docker and Docker Compose
- VPN subscription with WireGuard support (recommended: Mullvad, AirVPN, ProtonVPN)
- Port forwarding capability (optional, for better seeding)

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/GermanTorales/streaming-service.git
cd streaming-service
```

### 2. Configuration

#### VPN Setup (Gluetun)

Edit the VPN credentials in `docker-compose.yml`:

```yaml
environment:
  - VPN_SERVICE_PROVIDER=your_provider  # airvpn, mullvad, protonvpn, etc.
  - VPN_TYPE=wireguard
  - WIREGUARD_PRIVATE_KEY=your_private_key
  - WIREGUARD_PRESHARED_KEY=your_preshared_key
  - WIREGUARD_ADDRESSES=your_assigned_ip
  - SERVER_COUNTRIES=Netherlands,Switzerland
```

**Getting VPN Credentials:**
1. Log into your VPN provider's dashboard
2. Generate WireGuard configuration
3. Extract the required keys and addresses from the `.conf` file

#### FlexGet Configuration

Configure FlexGet in `flexget/config.yml`:

```yaml
templates:
  global:
    # Global settings for all tasks

tasks:
  organize_movies:
    # Movie organization rules
  organize_tv:
    # TV show organization rules
```

### 3. Directory Structure

Create the required directories:

```bash
mkdir -p {downloads,movies,tv_shows,flexget}
```

### 4. Launch Services

```bash
docker-compose up -d
```

## Usage

### Accessing Services

- **Transmission Web UI**: `http://localhost:9091`
- **Media Files**: Check organized directories (`./movies`, `./tv_shows`)

### Adding Torrents

1. Access Transmission web interface
2. Add torrent files or magnet links
3. FlexGet will automatically organize completed downloads

### Monitoring

#### Check VPN Status
```bash
docker compose exec gluetun curl ifconfig.me
```

#### FlexGet Logs
```bash
docker compose logs flexget
```

#### Transmission Status
```bash
docker compose logs transmission
```

## Configuration Details

### Gluetun (VPN)

```yaml
gluetun:
  image: qmcgaw/gluetun
  cap_add:
    - NET_ADMIN
  devices:
    - /dev/net/tun:/dev/net/tun
  environment:
    - VPN_SERVICE_PROVIDER=airvpn
    - VPN_TYPE=wireguard
    - WIREGUARD_PRIVATE_KEY=${WIREGUARD_PRIVATE_KEY}
    - WIREGUARD_PRESHARED_KEY=${WIREGUARD_PRESHARED_KEY}
    - WIREGUARD_ADDRESSES=${WIREGUARD_ADDRESSES}
    - SERVER_COUNTRIES=Netherlands
    - FIREWALL_OUTBOUND_SUBNETS=192.168.0.0/16
```

### Transmission

```yaml
transmission:
  image: lscr.io/linuxserver/transmission
  environment:
    - PUID=1000
    - PGID=1000
    - TZ=UTC
  volumes:
    - ./transmission:/config
    - ./downloads:/downloads
  network_mode: "service:gluetun"  # Routes through VPN
  depends_on:
    - gluetun
```

### FlexGet

```yaml
flexget:
  image: wiserain/flexget
  environment:
    - TZ=UTC
  volumes:
    - ./flexget:/config
    - ./downloads:/downloads
    - ./movies:/movies
    - ./tv_shows:/tv_shows
```

## File Organization

FlexGet automatically organizes media using these patterns:

### Movies
```
movies/
├── Action/
│   └── Movie Title (Year)/
│       └── Movie Title (Year).mkv
└── Drama/
    └── Another Movie (Year)/
        └── Another Movie (Year).mp4
```

### TV Shows
```
tv_shows/
├── Show Name/
│   ├── Season 01/
│   │   ├── S01E01 - Episode Title.mkv
│   │   └── S01E02 - Episode Title.mkv
│   └── Season 02/
│       └── S02E01 - Episode Title.mkv
```

## Performance Optimization

### VPN Server Selection
- **Netherlands**: Generally fastest for European users
- **Switzerland**: Good privacy laws and speed
- **Canada**: Good for North American users

### Transmission Settings
- **Peer Limit**: 200-300
- **Upload Slots**: 8-12
- **Speed Limits**: Set according to your connection
- **Port Forwarding**: Enable if your VPN supports it

### FlexGet Optimization
- **Schedule**: Run every 30-60 minutes
- **IMDB Lookup**: Enable for better metadata
- **Quality Filters**: Configure preferred resolutions

## Troubleshooting

### Common Issues

#### VPN Connection Problems
```bash
# Check VPN status
docker compose logs gluetun

# Verify IP address
docker compose exec gluetun curl ifconfig.me
```

#### Slow Download Speeds
```bash
# Test speed through VPN
docker exec gluetun wget -O /dev/null http://speedtest.wdc01.softlayer.com/downloads/test100.zip
```

#### FlexGet Not Organizing
```bash
# Check FlexGet logs
docker compose logs flexget

# Manual execution
docker compose exec flexget flexget execute --now
```

#### Permission Issues
```bash
# Fix ownership
sudo chown -R $USER:$USER downloads movies tv_shows
```

### Service Management

#### Restart Services
```bash
docker-compose restart
```

#### Update Containers
```bash
docker-compose pull
docker-compose up -d
```

#### Reset FlexGet Memory
```bash
docker exec flexget flexget reset-plugin seen
```

## Security Considerations

- All torrent traffic is routed through VPN
- No logs are kept by default
- Media files are organized locally
- Web interfaces are accessible only on local network

## Environment Variables

Create a `.env` file for sensitive information:

```env
# VPN Configuration
WIREGUARD_PRIVATE_KEY=your_private_key
WIREGUARD_PRESHARED_KEY=your_preshared_key
WIREGUARD_ADDRESSES=your_assigned_ip

# User Configuration
PUID=1000
PGID=1000
TZ=America/New_York
```

## Supported VPN Providers

- [AirVPN](https://airvpn.org/)
- [Mullvad](https://mullvad.net/)
- [ProtonVPN](https://protonvpn.com/)
- [Windscribe](https://windscribe.com/)
- [Surfshark](https://surfshark.com/)
- [And many more...](https://github.com/qdm12/gluetun/wiki)

## Tools and Dependencies

### Core Tools
- **Docker**: Container platform
- **Docker Compose**: Multi-container orchestration
- **Git**: Version control

### Container Images
- **qmcgaw/gluetun**: VPN client container
- **lscr.io/linuxserver/transmission**: BitTorrent client
- **wiserain/flexget**: Media automation tool

### Regular Maintenance
- **Weekly**: Check VPN connection and speeds
- **Monthly**: Update container images
- **As needed**: Clean up old torrents and completed downloads

## License

This project is for educational purposes. Ensure compliance with local laws regarding torrenting and media distribution.

## Disclaimer

This software is intended for downloading and organizing legally obtained media content. Users are responsible for ensuring their usage complies with applicable laws and regulations. The authors do not condone or encourage copyright infringement or illegal downloading.

---

**Note**: Always verify that your VPN is working properly before downloading any content. Check your public IP address to ensure you're protected.
