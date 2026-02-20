#!/usr/bin/env python3
"""
AniWorld Proxy Server
Resolves stream URLs on-demand via the API server and redirects.
Used by .strm files: http://localhost:5081/play/{slug}/{season}/{episode}
"""

import configparser
import logging
import os
import sys
import requests
from fastapi import FastAPI, HTTPException
from fastapi.responses import RedirectResponse
import uvicorn

# Config
CONFIG_PATH = os.environ.get("ANIWORLD_CONFIG", "/etc/aniworld/config.ini")
config = configparser.ConfigParser()
config.read(CONFIG_PATH)

API_PORT = config.getint("api", "port", fallback=5080)
PROXY_PORT = config.getint("proxy", "port", fallback=5081)
PREF_LANGUAGE = config.get("preferences", "language", fallback="Deutsch")
PREF_HOSTER = config.get("preferences", "hoster", fallback="VOE")

API_BASE = f"http://localhost:{API_PORT}"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
log = logging.getLogger("aniworld-proxy")

app = FastAPI(title="AniWorld Proxy", docs_url=None, redoc_url=None)


@app.get("/play/{slug}/{season}/{episode}")
async def play(slug: str, season: int, episode: int):
    """
    Resolve stream URL via API server and redirect (302).
    Called by Emby when playing a .strm file.
    """
    log.info(f"Play request: {slug} S{season}E{episode}")

    try:
        # Call API server to resolve stream
        resp = requests.post(
            f"{API_BASE}/api/resolve",
            json={
                "slug": slug,
                "season": season,
                "episode": episode
            },
            timeout=60
        )
        resp.raise_for_status()
        data = resp.json()
    except requests.RequestException as e:
        log.error(f"API request failed: {e}")
        raise HTTPException(status_code=502, detail="API server unreachable")

    if not data or not isinstance(data, list) or len(data) == 0:
        log.warning(f"No streams found for {slug} S{season}E{episode}")
        raise HTTPException(status_code=404, detail="No streams found")

    # Pick best stream based on language + hoster preference
    lang_priority = {"Deutsch": 0, "GerSub": 1, "EngSub": 2}
    hoster_priority = ["VOE", "Vidmoly", "Doodstream", "Streamtape", "Filemoon"]

    pref_lang_idx = lang_priority.get(PREF_LANGUAGE, 99)

    def sort_key(stream):
        lang_idx = lang_priority.get(stream.get("language", ""), 99)
        try:
            hoster_idx = hoster_priority.index(stream.get("name", ""))
        except ValueError:
            hoster_idx = 99
        return (lang_idx, hoster_idx)

    streams = sorted(data, key=sort_key)
    best = streams[0]
    stream_url = best.get("streamUrl", "")

    if not stream_url:
        log.warning(f"Best stream has no URL: {best}")
        raise HTTPException(status_code=404, detail="Stream URL empty")

    log.info(f"Redirecting to {best.get('name')} ({best.get('language')}): {stream_url[:80]}...")
    return RedirectResponse(url=stream_url, status_code=302)


@app.get("/health")
async def health():
    return {"status": "ok", "api": API_BASE}


if __name__ == "__main__":
    log.info(f"Starting AniWorld Proxy on port {PROXY_PORT}")
    log.info(f"API Server: {API_BASE}")
    uvicorn.run(app, host="0.0.0.0", port=PROXY_PORT, log_level="info")
