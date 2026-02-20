#!/bin/bash
# =========================================
# AniWorld for Emby - All-in-One Installer
# API Server + Metadata Server + Proxy + Sync
# Für Ubuntu 24.04 LTS / Debian 12+
# =========================================
set -e

INSTALL_DIR="/opt/aniworld"
DATA_DIR="/opt/aniworld/data"
CONFIG_DIR="/etc/aniworld"
MEDIA_DIR="/media/aniworld"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN} AniWorld for Emby - Installer${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "Installiert: API Server, Metadata Server, Stream Proxy, Sync Service"
echo ""

# Check root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Bitte als root ausführen (sudo ./install.sh)${NC}"
    exit 1
fi

# Check if emby user exists
if ! id -u emby &>/dev/null; then
    echo -e "${RED}Emby User nicht gefunden. Bitte zuerst Emby Server installieren.${NC}"
    exit 1
fi

# ── Config ──────────────────────────────────────────────────────────
echo -e "${YELLOW}Konfiguration:${NC}"
echo "(Enter drücken für Standardwert)"
echo ""

read -p "API Server Port [5080]: " API_PORT
API_PORT=${API_PORT:-5080}

read -p "Metadata Server Port [5090]: " META_PORT
META_PORT=${META_PORT:-5090}

read -p "Proxy Port [5081]: " PROXY_PORT
PROXY_PORT=${PROXY_PORT:-5081}

read -p "Media Pfad für .strm Dateien [$MEDIA_DIR]: " MEDIA_PATH
MEDIA_PATH=${MEDIA_PATH:-$MEDIA_DIR}

echo ""

# ── Python ──────────────────────────────────────────────────────────
echo -e "${YELLOW}Installiere System-Abhängigkeiten...${NC}"
apt-get update -qq
apt-get install -y -qq python3 python3-pip python3-venv > /dev/null 2>&1
echo -e "${GREEN}✅ Python installiert${NC}"

# ── Verzeichnisse ──────────────────────────────────────────────────
echo -e "${YELLOW}Erstelle Verzeichnisse...${NC}"
mkdir -p "$INSTALL_DIR" "$DATA_DIR" "$DATA_DIR/covers" "$CONFIG_DIR" "$MEDIA_PATH"

# ── Dateien kopieren ────────────────────────────────────────────────
echo -e "${YELLOW}Kopiere Dateien...${NC}"
cp "$SCRIPT_DIR/api_server.py" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/metadata_server.py" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/proxy.py" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/sync.py" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/requirements.txt" "$INSTALL_DIR/"
echo -e "${GREEN}✅ Dateien kopiert${NC}"

# ── Python venv ────────────────────────────────────────────────────
echo -e "${YELLOW}Erstelle Python venv + installiere Pakete...${NC}"
python3 -m venv "$INSTALL_DIR/venv"
"$INSTALL_DIR/venv/bin/pip" install -q -r "$INSTALL_DIR/requirements.txt"
echo -e "${GREEN}✅ Python Pakete installiert${NC}"

# ── Config schreiben ───────────────────────────────────────────────
echo -e "${YELLOW}Schreibe Config...${NC}"
cat > "$CONFIG_DIR/config.ini" << EOF
[api]
port = $API_PORT
db_path = $DATA_DIR/aniworld.db

[metadata]
port = $META_PORT
db_path = $DATA_DIR/metadata.db
covers_dir = $DATA_DIR/covers
anidb_titles_path = $DATA_DIR/anidb-titles.xml.gz

[proxy]
port = $PROXY_PORT

[sync]
media_path = $MEDIA_PATH

[preferences]
language = Deutsch
hoster = VOE
EOF
echo -e "${GREEN}✅ Config: $CONFIG_DIR/config.ini${NC}"

# ── systemd Services ───────────────────────────────────────────────
echo -e "${YELLOW}Installiere systemd Services...${NC}"

cat > /etc/systemd/system/aniworld-api.service << EOF
[Unit]
Description=AniWorld API Server
After=network.target

[Service]
Type=simple
User=emby
Group=emby
ExecStart=$INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/api_server.py
Environment=ANIWORLD_CONFIG=$CONFIG_DIR/config.ini
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/aniworld-metadata.service << EOF
[Unit]
Description=AniWorld Metadata Server
After=network.target aniworld-api.service

[Service]
Type=simple
User=emby
Group=emby
ExecStart=$INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/metadata_server.py
Environment=ANIWORLD_CONFIG=$CONFIG_DIR/config.ini
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/aniworld-proxy.service << EOF
[Unit]
Description=AniWorld Stream Proxy
After=network.target aniworld-api.service

[Service]
Type=simple
User=emby
Group=emby
ExecStart=$INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/proxy.py
Environment=ANIWORLD_CONFIG=$CONFIG_DIR/config.ini
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/aniworld-sync.service << EOF
[Unit]
Description=AniWorld Sync Service
After=network.target aniworld-api.service aniworld-metadata.service

[Service]
Type=oneshot
User=emby
Group=emby
ExecStart=$INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/sync.py
Environment=ANIWORLD_CONFIG=$CONFIG_DIR/config.ini
EOF

cat > /etc/systemd/system/aniworld-sync.timer << EOF
[Unit]
Description=AniWorld Sync Timer (daily 03:00)

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

echo -e "${GREEN}✅ systemd Services erstellt${NC}"

# ── Berechtigungen ─────────────────────────────────────────────────
echo -e "${YELLOW}Setze Berechtigungen...${NC}"
chown -R emby:emby "$INSTALL_DIR" "$DATA_DIR" "$CONFIG_DIR" "$MEDIA_PATH"

# ── Services starten ───────────────────────────────────────────────
echo -e "${YELLOW}Starte Services...${NC}"
systemctl daemon-reload

# Stop alte Services falls vorhanden
systemctl stop aniworld-api aniworld-metadata aniworld-proxy aniworld-sync-proxy 2>/dev/null || true

systemctl enable aniworld-api aniworld-metadata aniworld-proxy aniworld-sync.timer
systemctl start aniworld-api
sleep 2
systemctl start aniworld-metadata
sleep 1
systemctl start aniworld-proxy
systemctl start aniworld-sync.timer

echo -e "${GREEN}✅ Services gestartet${NC}"

# ── Status Check ───────────────────────────────────────────────────
echo ""
sleep 2
echo -e "${YELLOW}Service Status:${NC}"
for svc in aniworld-api aniworld-metadata aniworld-proxy; do
    if systemctl is-active --quiet $svc; then
        echo -e "  ${GREEN}✅ $svc${NC}"
    else
        echo -e "  ${RED}❌ $svc (check: journalctl -u $svc)${NC}"
    fi
done

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN} ✅ Installation abgeschlossen!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "Services:"
echo "  API Server:      http://localhost:$API_PORT/api/status"
echo "  Metadata Server: http://localhost:$META_PORT/status"
echo "  Stream Proxy:    http://localhost:$PROXY_PORT/health"
echo ""
echo "Daten:  $DATA_DIR"
echo "Media:  $MEDIA_PATH"
echo "Config: $CONFIG_DIR/config.ini"
echo ""
echo -e "${YELLOW}Nächste Schritte:${NC}"
echo ""
echo "1. Initiales Scraping starten (dauert ~30min):"
echo "   curl -X POST http://localhost:$API_PORT/api/sync"
echo "   curl -X POST http://localhost:$API_PORT/api/sync/details"
echo ""
echo "2. Warten bis Details gescraped sind, dann Sync starten:"
echo "   sudo systemctl start aniworld-sync"
echo ""
echo "3. In Emby: Neue Bibliothek erstellen"
echo "   Typ:  TV-Sendungen"
echo "   Pfad: $MEDIA_PATH"
echo "   Name: AniWorld"
echo ""
echo "4. Emby Library Scan starten"
echo ""
