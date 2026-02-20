#!/usr/bin/env python3
"""
AniWorld Sync Service
Syncs anime data from API + Metadata servers into .strm/.nfo files for Emby.
"""

import configparser
import logging
import os
import re
import sys
import requests
import xml.etree.ElementTree as ET
from xml.dom import minidom
from pathlib import Path

# Config
CONFIG_PATH = os.environ.get("ANIWORLD_CONFIG", "/etc/aniworld/config.ini")
config = configparser.ConfigParser()
config.read(CONFIG_PATH)

API_SERVER = config.get("api", "server", fallback="localhost")
API_PORT = config.getint("api", "port", fallback=5080)
META_SERVER = config.get("metadata", "server", fallback="localhost")
META_PORT = config.getint("metadata", "port", fallback=5090)
PROXY_PORT = config.getint("proxy", "port", fallback=5081)
MEDIA_PATH = config.get("sync", "media_path", fallback="/media/aniworld")

API_BASE = f"http://{API_SERVER}:{API_PORT}"
META_BASE = f"http://{META_SERVER}:{META_PORT}"
PROXY_BASE = f"http://localhost:{PROXY_PORT}"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
log = logging.getLogger("aniworld-sync")


def safe_filename(name):
    """Remove/replace characters not safe for filenames."""
    name = re.sub(r'[<>:"/\\|?*]', '', name)
    name = name.strip('. ')
    return name


def pretty_xml(elem):
    """Convert ElementTree element to pretty-printed XML string."""
    rough = ET.tostring(elem, encoding='unicode')
    parsed = minidom.parseString(rough)
    return parsed.toprettyxml(indent="  ", encoding=None)


def fetch_all_anime():
    """Fetch all anime from API server."""
    log.info("Fetching anime list from API server...")
    try:
        resp = requests.get(f"{API_BASE}/api/anime", timeout=30)
        resp.raise_for_status()
        data = resp.json()
        log.info(f"Got {len(data)} anime")
        return data
    except Exception as e:
        log.error(f"Failed to fetch anime list: {e}")
        return []


def fetch_episodes(slug):
    """Fetch episodes for an anime from API server."""
    try:
        resp = requests.get(f"{API_BASE}/api/anime/{slug}/episodes", timeout=30)
        resp.raise_for_status()
        return resp.json()
    except Exception as e:
        log.error(f"Failed to fetch episodes for {slug}: {e}")
        return []


def fetch_metadata(slug):
    """Fetch metadata from Metadata server."""
    try:
        resp = requests.get(f"{META_BASE}/api/metadata/{slug}", timeout=15)
        if resp.status_code == 404:
            return None
        resp.raise_for_status()
        return resp.json()
    except Exception as e:
        log.warning(f"Failed to fetch metadata for {slug}: {e}")
        return None


def download_cover(url, dest_path):
    """Download cover image to dest_path if not already cached."""
    if os.path.exists(dest_path):
        return True
    try:
        resp = requests.get(url, timeout=15)
        resp.raise_for_status()
        os.makedirs(os.path.dirname(dest_path), exist_ok=True)
        with open(dest_path, 'wb') as f:
            f.write(resp.content)
        return True
    except Exception as e:
        log.warning(f"Failed to download cover: {e}")
        return False


def write_tvshow_nfo(show_dir, anime_name, metadata):
    """Write tvshow.nfo for an anime series."""
    nfo_path = os.path.join(show_dir, "tvshow.nfo")

    root = ET.Element("tvshow")
    ET.SubElement(root, "title").text = anime_name
    ET.SubElement(root, "sorttitle").text = anime_name

    if metadata:
        if metadata.get("description"):
            ET.SubElement(root, "plot").text = metadata["description"]
        if metadata.get("genres"):
            for genre in metadata["genres"]:
                ET.SubElement(root, "genre").text = genre
        if metadata.get("rating"):
            ET.SubElement(root, "rating").text = str(metadata["rating"])
        if metadata.get("year"):
            ET.SubElement(root, "year").text = str(metadata["year"])
        if metadata.get("studio"):
            ET.SubElement(root, "studio").text = metadata["studio"]

    with open(nfo_path, 'w', encoding='utf-8') as f:
        f.write(pretty_xml(root))


def write_episode_nfo(nfo_path, anime_name, season, episode, title=None, metadata=None):
    """Write episode .nfo file."""
    root = ET.Element("episodedetails")
    ET.SubElement(root, "title").text = title or f"Episode {episode}"
    ET.SubElement(root, "showtitle").text = anime_name
    ET.SubElement(root, "season").text = str(season)
    ET.SubElement(root, "episode").text = str(episode)

    if metadata and metadata.get("description"):
        ET.SubElement(root, "plot").text = metadata.get("description", "")

    with open(nfo_path, 'w', encoding='utf-8') as f:
        f.write(pretty_xml(root))


def write_strm(strm_path, slug, season, episode):
    """Write .strm file pointing to local proxy."""
    url = f"{PROXY_BASE}/play/{slug}/{season}/{episode}"
    with open(strm_path, 'w', encoding='utf-8') as f:
        f.write(url + '\n')


def sync_anime(anime, metadata):
    """Sync one anime series: create dirs, .strm, .nfo, covers."""
    slug = anime.get("slug", "")
    name = anime.get("name", slug)
    safe_name = safe_filename(name)
    show_dir = os.path.join(MEDIA_PATH, safe_name)
    os.makedirs(show_dir, exist_ok=True)

    # Write tvshow.nfo
    write_tvshow_nfo(show_dir, name, metadata)

    # Download cover
    cover_url = None
    if metadata and metadata.get("coverUrl"):
        cover_url = metadata["coverUrl"]
    elif anime.get("coverUrl"):
        cover_url = anime["coverUrl"]

    if cover_url:
        # Try to get from metadata server first
        ext = "jpg"
        if ".png" in cover_url:
            ext = "png"
        poster_path = os.path.join(show_dir, f"poster.{ext}")
        meta_cover = f"{META_BASE}/api/cover/{slug}"
        if not download_cover(meta_cover, poster_path):
            download_cover(cover_url, poster_path)

    # Fetch and write episodes
    episodes = fetch_episodes(slug)
    if not episodes:
        return 0

    ep_count = 0
    for ep in episodes:
        season = ep.get("season", 1)
        ep_num = ep.get("episode", 1)
        ep_title = ep.get("title", f"Episode {ep_num}")

        # Season directory
        if season == 0:
            season_dir = os.path.join(show_dir, "Specials")
        else:
            season_dir = os.path.join(show_dir, f"Season {season:02d}")
        os.makedirs(season_dir, exist_ok=True)

        # Filename: "Anime - SXXEXX - Title.strm"
        safe_title = safe_filename(ep_title)
        if season == 0:
            base_name = f"{safe_name} - S00E{ep_num:02d} - {safe_title}"
        else:
            base_name = f"{safe_name} - S{season:02d}E{ep_num:02d} - {safe_title}"

        strm_path = os.path.join(season_dir, f"{base_name}.strm")
        nfo_path = os.path.join(season_dir, f"{base_name}.nfo")

        # Only write .strm if it doesn't exist (URLs are stable via proxy)
        if not os.path.exists(strm_path):
            write_strm(strm_path, slug, season, ep_num)
            ep_count += 1

        # Always update .nfo (metadata might change)
        write_episode_nfo(nfo_path, name, season, ep_num, ep_title)

    return ep_count


def main():
    log.info("=" * 60)
    log.info("AniWorld Sync starting")
    log.info(f"API: {API_BASE} | Metadata: {META_BASE}")
    log.info(f"Media path: {MEDIA_PATH}")
    log.info("=" * 60)

    os.makedirs(MEDIA_PATH, exist_ok=True)

    anime_list = fetch_all_anime()
    if not anime_list:
        log.error("No anime found, aborting sync")
        sys.exit(1)

    total_new = 0
    for i, anime in enumerate(anime_list):
        slug = anime.get("slug", "")
        name = anime.get("name", slug)
        log.info(f"[{i+1}/{len(anime_list)}] Syncing: {name}")

        metadata = fetch_metadata(slug)
        new_eps = sync_anime(anime, metadata)
        if new_eps > 0:
            log.info(f"  → {new_eps} new episodes written")
        total_new += new_eps

    log.info("=" * 60)
    log.info(f"Sync complete: {len(anime_list)} anime, {total_new} new episodes")
    log.info("=" * 60)


if __name__ == "__main__":
    main()
