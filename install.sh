#!/bin/bash
# AniWorld Sync+Proxy Installer
# Für Ubuntu 24.04 LTS / Debian 12+
set -e

INSTALL_DIR="/opt/aniworld-sync-proxy"
CONFIG_DIR="/etc/aniworld"
MEDIA_DIR="/media/aniworld"

echo "========================================="
echo " AniWorld Sync+Proxy Installer"
echo "========================================="

# Check root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Bitte als root ausführen (sudo)"
    exit 1
fi

# Prompt for config
read -p "API Server IP [192.168.178.96]: " API_SERVER
API_SERVER=${API_SERVER:-192.168.178.96}

read -p "API Port [5080]: " API_PORT
API_PORT=${API_PORT:-5080}

read -p "Metadata Server IP [$API_SERVER]: " META_SERVER
META_SERVER=${META_SERVER:-$API_SERVER}

read -p "Metadata Port [5090]: " META_PORT
META_PORT=${META_PORT:-5090}

read -p "Proxy Port [5081]: " PROXY_PORT
PROXY_PORT=${PROXY_PORT:-5081}

read -p "Media Pfad [$MEDIA_DIR]: " MEDIA_PATH
MEDIA_PATH=${MEDIA_PATH:-$MEDIA_DIR}

echo ""
echo "📦 Installiere Python-Abhängigkeiten..."
apt-get update -qq
apt-get install -y -qq python3 python3-pip python3-venv > /dev/null

echo "📁 Erstelle Verzeichnisse..."
mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$MEDIA_PATH"

echo "📋 Kopiere Dateien..."
cp proxy.py sync.py requirements.txt "$INSTALL_DIR/"

echo "🐍 Erstelle Python venv..."
python3 -m venv "$INSTALL_DIR/venv"
"$INSTALL_DIR/venv/bin/pip" install -q -r "$INSTALL_DIR/requirements.txt"

# Update service files to use venv python
echo "⚙️  Schreibe Config..."
cat > "$CONFIG_DIR/config.ini" << EOF
[api]
server = $API_SERVER
port = $API_PORT

[metadata]
server = $META_SERVER
port = $META_PORT

[proxy]
port = $PROXY_PORT

[sync]
media_path = $MEDIA_PATH

[preferences]
language = Deutsch
hoster = VOE
EOF

echo "🔧 Installiere systemd Services..."

cat > /etc/systemd/system/aniworld-proxy.service << EOF
[Unit]
Description=AniWorld Stream Proxy
After=network.target

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
After=network.target

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

# Set permissions
chown -R emby:emby "$MEDIA_PATH"
chown -R emby:emby "$INSTALL_DIR"
chown -R emby:emby "$CONFIG_DIR"

# Enable and start services
systemctl daemon-reload
systemctl enable aniworld-proxy
systemctl start aniworld-proxy
systemctl enable aniworld-sync.timer
systemctl start aniworld-sync.timer

echo ""
echo "========================================="
echo " ✅ Installation abgeschlossen!"
echo "========================================="
echo ""
echo "Proxy:  http://localhost:$PROXY_PORT/health"
echo "Media:  $MEDIA_PATH"
echo "Config: $CONFIG_DIR/config.ini"
echo ""
echo "Nächste Schritte:"
echo "1. Ersten Sync manuell starten:"
echo "   sudo systemctl start aniworld-sync"
echo ""
echo "2. In Emby: Neue TV-Show Bibliothek erstellen"
echo "   Pfad: $MEDIA_PATH"
echo "   Name: AniWorld"
echo ""
echo "3. Emby Library Scan starten"
echo ""
