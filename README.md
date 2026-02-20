# AniWorld Sync+Proxy für Emby

Anime-Streaming von aniworld.to direkt in Emby - als native TV-Show Library statt Channel-Plugin.

## Features

- **Volle Emby Integration:** Auto-Play, Resume, Per-User Zugriff, Suche, Metadata
- **Automatischer Sync:** Holt Anime-Daten + Metadata und erstellt .strm/.nfo Dateien
- **Stream Proxy:** Löst Hoster-URLs on-demand auf (302 Redirect)
- **Kein Plugin nötig:** Alles über Standard-Emby-Bibliothek

## Voraussetzungen

- Emby Server (4.8+)
- AniWorld API Server (remote)
- AniWorld Metadata Server (remote)
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
[Sync täglich] → API + Metadata Server → .strm + .nfo Dateien → Emby Library

[User klickt Play] → .strm → localhost:5081/play/slug/s/e → API resolve → 302 → Stream
```

## Services

| Service | Beschreibung |
|---------|-------------|
| `aniworld-proxy` | Stream-Proxy (Port 5081) |
| `aniworld-sync.timer` | Täglicher Sync (03:00) |

## Manueller Sync

```bash
sudo systemctl start aniworld-sync
```

## Config

`/etc/aniworld/config.ini` - API Server, Metadata Server, Proxy Port, Media Pfad, Sprache, Hoster
