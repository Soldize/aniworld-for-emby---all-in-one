# AniWorld for Emby - All-in-One

Anime-Streaming von aniworld.to in Emby - als native TV-Show Library.

**Alles läuft lokal auf dem Emby-Server** - kein separater API/Metadata Server nötig.

## Features

- **Volle Emby Integration:** Auto-Play, Resume, Per-User Zugriff, Suche, Metadata
- **API Server:** Scrapt aniworld.to, cached Episoden + Stream-URLs
- **Metadata Server:** AniList/MAL/AniDB Metadata, Cover-Bilder, Genres, Ratings
- **Stream Proxy:** Löst Hoster-URLs on-demand auf (302 Redirect)
- **Sync Service:** Erstellt .strm/.nfo Dateien für Emby Library
- **Kein Plugin nötig:** Alles über Standard-Emby-Bibliothek

## Voraussetzungen

- Emby Server (4.8+)
- Python 3.10+
- Ubuntu 24.04 LTS / Debian 12+

## Installation

```bash
git clone https://github.com/Soldize/emby-aniworld-sync-proxy.git
cd emby-aniworld-sync-proxy
sudo ./install.sh
```

## Architektur

```
                    ┌─────────────────────────────────┐
                    │         Emby Server              │
                    │                                  │
                    │  ┌──────────┐  ┌──────────────┐  │
                    │  │API Server│  │Metadata Server│  │
                    │  │ :5080    │  │ :5090         │  │
                    │  └────┬─────┘  └──────┬───────┘  │
                    │       │               │          │
                    │  ┌────┴───────────────┴───────┐  │
                    │  │      Sync Service          │  │
                    │  │  (täglich 03:00)            │  │
                    │  └────────────┬───────────────┘  │
                    │               │                  │
                    │  ┌────────────▼───────────────┐  │
                    │  │  /media/aniworld/          │  │
                    │  │  ├── Anime Name/           │  │
                    │  │  │   ├── tvshow.nfo        │  │
                    │  │  │   ├── poster.jpg        │  │
                    │  │  │   └── Season 01/        │  │
                    │  │  │       ├── *.strm         │  │
                    │  │  │       └── *.nfo          │  │
                    │  └───────────────────────────┘  │
                    │                                  │
                    │  ┌──────────────────────────┐   │
                    │  │     Stream Proxy :5081    │   │
                    │  │  .strm → resolve → 302   │   │
                    │  └──────────────────────────┘   │
                    └─────────────────────────────────┘
```

## Services

| Service | Port | Beschreibung |
|---------|------|-------------|
| `aniworld-api` | 5080 | API Server (Scraping, Stream-Resolution) |
| `aniworld-metadata` | 5090 | Metadata Server (AniList/MAL/AniDB) |
| `aniworld-proxy` | 5081 | Stream Proxy (.strm Redirect) |
| `aniworld-sync.timer` | - | Täglicher Sync (03:00) |

## Manueller Sync

```bash
# Erst Katalog + Details scrapen
curl -X POST http://localhost:5080/api/sync
curl -X POST http://localhost:5080/api/sync/details

# Dann .strm Dateien generieren
sudo systemctl start aniworld-sync
```

## Config

`/etc/aniworld/config.ini`

## Daten

`/opt/aniworld/data/` - Datenbanken, Cover-Cache
`/media/aniworld/` - .strm/.nfo Dateien (Emby Library)
