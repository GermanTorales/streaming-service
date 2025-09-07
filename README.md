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
- **[Plex](https://www.plex.tv/media-server-downloads/?cat=computer&plat=linux)** - Media streaming Plex server

### Features

- [x] All torrent traffic routed through VPN
- [x] Manual addig movies
- [x] Manual adding tv shows
- [x] Manual adding animes
- [x] Automatic movies download
- [ ] Automatic tv shows download
- [ ] Automatic animes download
- [x] Automatic movies organization
- [ ] Automatic tv show organization
- [ ] Automatic anime organization
- [x] Automatic completed torrents cleaner
- [x] Automatic stalled torrents cleaner
- [ ] Automatic dead torrents cleaner
- [ ] Manual purge all torrents
- [x] Local Plex server

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

Environment Variables:
Copy the `.env.example` and set the correct values.

```sh
cp .env.examples ./env
```

#### VPN Setup (Gluetun)

**Getting VPN Credentials:**
1. Log into your VPN provider's dashboard
2. Generate WireGuard configuration
3. Extract the required keys and addresses from the `.conf` file

#### FlexGet Configuration

The main configuration of FlexGet is in `./flexget/config/config.yml`

You can add or remove settings more easily, you only need to add or remove news:
- Templates
- Tasks

The templates are in `./flexget/config/templates`
The tasks are in `./flexget/config/tasks`

Each folder contains `.yml` subfiles with the name of the task or template. You only need to write the configuration; you don't need to add the type (task or template) or name.

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

## Security Considerations

- All torrent traffic is routed through VPN
- No logs are kept by default
- Media files are organized locally
- Web interfaces are accessible only on local network

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

## License

This project is for educational purposes. Ensure compliance with local laws regarding torrenting and media distribution.

## Disclaimer

This software is intended for downloading and organizing legally obtained media content. Users are responsible for ensuring their usage complies with applicable laws and regulations. The authors do not condone or encourage copyright infringement or illegal downloading.

---

**Note**: Always verify that your VPN is working properly before downloading any content. Check your public IP address to ensure you're protected.
