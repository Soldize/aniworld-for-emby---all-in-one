#!/bin/bash
# WARP Health Check - runs every 15 minutes via systemd timer
# Checks WARP connectivity and reconnects if unhealthy,
# but ONLY when no active streams are playing.

PROXY_PORT="${PROXY_PORT:-5080}"
WARP_PROXY="socks5://127.0.0.1:40000"
LOG_TAG="warp-health"

log() { logger -t "$LOG_TAG" "$1"; echo "$(date '+%Y-%m-%d %H:%M:%S') $1"; }

# 1. Check if WARP is running
if ! warp-cli --accept-tos status 2>/dev/null | grep -q "Connected"; then
    log "WARP not connected - attempting connect..."
    warp-cli --accept-tos connect
    sleep 3
    if warp-cli --accept-tos status 2>/dev/null | grep -q "Connected"; then
        log "WARP reconnected successfully"
    else
        log "ERROR: WARP reconnect failed"
    fi
    exit 0
fi

# 2. Test WARP connectivity to hosters
VOE_OK=false
VIDMOLY_OK=false

if curl -s --socks5 127.0.0.1:40000 --max-time 5 -o /dev/null -w "%{http_code}" https://voe.sx | grep -q "200"; then
    VOE_OK=true
fi

if curl -s --socks5 127.0.0.1:40000 --max-time 5 -o /dev/null -w "%{http_code}" https://vidmoly.biz | grep -q "200"; then
    VIDMOLY_OK=true
fi

if $VOE_OK && $VIDMOLY_OK; then
    log "WARP healthy - VOE: OK, Vidmoly: OK"
    exit 0
fi

log "WARP unhealthy - VOE: $VOE_OK, Vidmoly: $VIDMOLY_OK"

# 3. Check for active streams before reconnecting
ACTIVE=$(curl -s --max-time 3 "http://localhost:${PROXY_PORT}/stream/active" 2>/dev/null)
SESSIONS=$(echo "$ACTIVE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('active_sessions', 0))" 2>/dev/null || echo "0")

if [ "$SESSIONS" -gt 0 ]; then
    log "Skipping reconnect - $SESSIONS active stream(s)"
    exit 0
fi

# 4. No active streams - safe to reconnect
log "No active streams - reconnecting WARP..."
warp-cli --accept-tos disconnect
sleep 2
warp-cli --accept-tos connect
sleep 3

# 5. Verify
if warp-cli --accept-tos status 2>/dev/null | grep -q "Connected"; then
    log "WARP reconnected successfully"
else
    log "ERROR: WARP reconnect failed after health check"
fi
