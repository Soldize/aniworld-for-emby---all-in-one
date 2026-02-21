# PLAN.md - Emby AniWorld Sync+Proxy

## Ziel
Ersetzt das Channel-Plugin durch einen Strm-File-Ansatz:
- Volle Emby Library Integration (Auto-Play, Resume, Per-User, Search, Metadata)
- Alles läuft auf dem Emby-Server
- Installierbar via Standalone Install-Script auf jedem Emby-Server

## Architektur

```
[Sync-Service] ---> [API-Server :5080] ---> Anime/Episoden-Daten (aniworld.to)
      |         ---> [Metadata-Server :5090] ---> Cover, Beschreibungen (AniList/MAL)
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

[Dashboard :5081]
  → Web-UI zum Steuern (Status, Sync, Detail-Scrape, Config)
```

## Komponenten

### 1. API-Server (Python/Flask, Port 5080)
- Scrapt aniworld.to, cached Anime-Katalog + Episoden in SQLite
- Stream-URL Resolution (Hoster auflösen)
- Background: Auto-Sync Katalog + Detail-Batches beim Start
- Nightly Episode-Scrape (02:00 UTC)
- systemd Service: `aniworld-api`

### 2. Metadata-Server (Python/Flask, Port 5090)
- AniList (primär) / Jikan/MAL (Fallback) / AniDB Metadata
- Cover-Bilder lokal gecacht
- Beschreibungen, Genres, Ratings
- systemd Service: `aniworld-metadata`

### 3. Proxy-Server + Dashboard (Python/FastAPI, Port 5081)
- `GET /play/{slug}/{season}/{episode}` → Stream resolve → 302 Redirect
- Web-Dashboard (`/`) mit:
  - Service-Status (API, Metadata, Proxy, Sync)
  - Sync Control (Start/Stop mit Live-Log)
  - Detail Scrape (Batch + Einzeln per Slug, Fortschrittsbalken)
  - Config Editor (direkt im Browser bearbeiten)
- Responsive Layout (Desktop, Tablet, Mobile)
- systemd Service: `aniworld-proxy`

### 4. Sync-Service (Python)
- Holt Anime-Liste + Episoden vom API-Server
- Holt Metadata vom Metadata-Server
- Schreibt .strm + .nfo + Cover
- Ordnerstruktur Emby-kompatibel (TV Show format)
- systemd Timer: täglich 03:00 (`aniworld-sync.timer`)

### 5. Config (/etc/aniworld/config.ini)
- API Port, DB-Pfad
- Metadata Port, DB-Pfad, Covers-Dir
- Proxy Port
- Media-Pfad (default: /media/aniworld)
- Sprache + Hoster Präferenz

### 6. Install-Script (Standalone)
- Einzelne Datei, lädt alles von GitHub
- Interaktives Menü (7 Optionen):
  1. Komplettinstallation
  2. Auf Updates prüfen (GitHub Release/Commit check)
  3. Config ändern
  4. Services neustarten
  5. Status
  6. Deinstallieren
  7. Anleitung (Ersteinrichtung, Dashboard, Fehlerbehebung)
- Post-Install Health-Check (Services + API + Dashboard)
- CLI-Shortcuts: `./install.sh install|update|status`

## Status

### ✅ Fertig
- [x] API-Server (Katalog-Scraping, Detail-Scraping, Stream-Resolution)
- [x] Metadata-Server (AniList/MAL/AniDB, Cover-Cache)
- [x] Proxy-Server (Stream-Redirect)
- [x] Dashboard (Status, Sync, Detail-Scrape mit Fortschrittsbalken, Config)
- [x] Dashboard responsive (Desktop/Tablet/Mobile)
- [x] Sync-Service (.strm/.nfo Generator)
- [x] Config-System (/etc/aniworld/config.ini)
- [x] systemd Services + Timer
- [x] Standalone Install-Script (lädt von GitHub)
- [x] Install-Menü mit Update-Check, Anleitung, Health-Check
- [x] Git: Gitea (meeko/) + GitHub (Soldize/)

### 🔨 Offen / Nice-to-have
- [ ] GitHub Release erstellen (für sauberen Update-Check)
- [ ] Dashboard: Anime-Suche / Katalog-Browser
- [ ] Dashboard: Log-Viewer für API/Metadata Server
- [ ] Dashboard: Auth/Passwort-Schutz
- [ ] Emby Library Auto-Setup (via Emby API)
