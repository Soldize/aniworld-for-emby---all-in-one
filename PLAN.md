# PLAN.md - Emby AniWorld Sync+Proxy

## Ziel
Ersetzt das Channel-Plugin durch einen Strm-File-Ansatz:
- Volle Emby Library Integration (Auto-Play, Resume, Per-User, Search, Metadata)
- Alles läuft auf dem Emby-Server
- Installierbar via Install-Script auf jedem Emby-Server

## Architektur

```
[Sync-Service] ---> [API-Server (remote)] ---> Anime/Episoden-Daten
      |          ---> [Metadata-Server (remote)] ---> Cover, Beschreibungen
      v
  /media/aniworld/
  ├── Anime Name/
  │   ├── tvshow.nfo
  │   ├── poster.jpg
  │   ├── Season 01/
  │   │   ├── Anime - S01E01 - Titel.strm
  │   │   ├── Anime - S01E01 - Titel.nfo
  │   │   └── ...

[User klickt Play]
  .strm → http://localhost:5081/play/slug/season/episode
  → Proxy-Server → API-Server resolve → 302 Redirect → Hoster-Stream
```

## Komponenten

### 1. Proxy-Server (Python/FastAPI, Port 5081)
- `GET /play/{slug}/{season}/{episode}` → Stream resolve → 302 Redirect
- Konfigurierbar: API-Server Adresse, Sprache, Hoster-Präferenz
- systemd Service: `aniworld-proxy`

### 2. Sync-Service (Python)
- Holt Anime-Liste + Episoden vom API-Server
- Holt Metadata vom Metadata-Server
- Schreibt .strm + .nfo + Cover
- Ordnerstruktur Emby-kompatibel (TV Show format)
- systemd Timer: täglich 03:00

### 3. Config (/etc/aniworld/config.ini)
- API_SERVER, API_PORT
- METADATA_SERVER, METADATA_PORT
- PROXY_PORT (default: 5081)
- MEDIA_PATH (default: /media/aniworld)
- PREFERRED_LANGUAGE, PREFERRED_HOSTER

### 4. Install-Script
- Installiert Python deps, systemd Services
- Erstellt Config
- Richtet Emby Library ein

## Status

### 🔨 In Arbeit
- [ ] Proxy-Server
- [ ] Sync-Service
- [ ] .nfo Generator
- [ ] Config
- [ ] systemd Services
- [ ] Install-Script
- [ ] Testen

### ✅ Fertig
(noch nix)
