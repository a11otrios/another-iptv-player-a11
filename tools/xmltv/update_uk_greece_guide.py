"""Download and merge the compact UK and Greek XMLTV guides used by the app."""

from __future__ import annotations

import argparse
import gzip
import json
import os
import tempfile
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone
from pathlib import Path


SOURCES = (
    "https://epgshare01.online/epgshare01/epg_ripper_UK1.xml.gz",
    "https://epgshare01.online/epgshare01/epg_ripper_GR1.xml.gz",
)

ERT_CHANNELS = (
    ("ert1", "ERT1.gr", "ERT 1"),
    ("ert2", "ERT2.gr", "ERT 2"),
    ("ert3", "ERT3.gr", "ERT 3"),
    ("ertnews", "ERTNews.gr", "ERT News"),
    ("ertworld", "ERTWorld.gr", "ERT World"),
)


def default_output() -> Path:
    local_app_data = os.environ.get("LOCALAPPDATA")
    if not local_app_data:
        raise RuntimeError("LOCALAPPDATA is not set; pass --output explicitly.")
    return Path(local_app_data) / "Another IPTV Player" / "epg" / "uk-greece.xml"


def download(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "Another-IPTV-Player/1.0"})
    with urllib.request.urlopen(request, timeout=90) as response:
        return gzip.decompress(response.read())


def xmltv_time(value: str) -> str:
    timestamp = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return timestamp.astimezone(timezone.utc).strftime("%Y%m%d%H%M%S +0000")


def cosmote_ert_programmes() -> tuple[list[ET.Element], list[ET.Element]]:
    channels: list[ET.Element] = []
    programmes: list[ET.Element] = []
    start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    headers = {
        "User-Agent": "Mozilla/5.0",
        "Referer": "https://www.cosmotetv.gr/",
        "Origin": "https://www.cosmotetv.gr",
        "Accept": "application/json",
    }
    for call_sign, xmltv_id, display_name in ERT_CHANNELS:
        items = []
        for day_offset in range(5):
            day_start = start + timedelta(days=day_offset)
            query = urllib.parse.urlencode({
                "from": int(day_start.timestamp()),
                "to": int((day_start + timedelta(days=1)).timestamp()),
                "callSigns": call_sign,
                "endingIncludedInRange": "false",
            })
            request = urllib.request.Request(
                "https://mwapi-prod.cosmotetvott.gr/api/v3.4/epg/listings/el?" + query,
                headers=headers,
            )
            with urllib.request.urlopen(request, timeout=60) as response:
                payload = json.load(response)
            items.extend(payload.get("channels", [{}])[0].get("items", []))
        if not items:
            raise RuntimeError(f"Cosmote returned no EPG data for {call_sign}.")
        channel = ET.Element("channel", {"id": xmltv_id})
        ET.SubElement(channel, "display-name").text = display_name
        channels.append(channel)
        for item in items:
            programme = ET.Element("programme", {
                "channel": xmltv_id,
                "start": xmltv_time(item["startTime"]),
                "stop": xmltv_time(item["endTime"]),
            })
            ET.SubElement(programme, "title").text = item.get("title", "").strip()
            description = item.get("description", "").strip()
            if description:
                ET.SubElement(programme, "desc").text = description
            programmes.append(programme)
    return channels, programmes


def update(output: Path) -> None:
    root = ET.Element("tv", {"generator-info-name": "Another IPTV Player XMLTV updater"})
    channel_ids: set[str] = set()
    programme_ids: set[tuple[str, str, str]] = set()
    def append(channel: ET.Element | None = None, programme: ET.Element | None = None) -> None:
        if channel is not None:
            channel_id = channel.get("id", "").strip()
            if channel_id and channel_id not in channel_ids:
                root.append(channel)
                channel_ids.add(channel_id)
        if programme is not None:
            key = (
                programme.get("channel", ""),
                programme.get("start", ""),
                (programme.findtext("title") or "").strip(),
            )
            if key not in programme_ids:
                root.append(programme)
                programme_ids.add(key)

    for source in SOURCES:
        document = ET.fromstring(download(source))
        for channel in document.findall("channel"):
            append(channel=channel)
        for programme in document.findall("programme"):
            append(programme=programme)
    ert_channels, ert_programmes = cosmote_ert_programmes()
    for channel in ert_channels:
        append(channel=channel)
    for programme in ert_programmes:
        append(programme=programme)

    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("wb", dir=output.parent, delete=False) as temporary:
        ET.ElementTree(root).write(temporary, encoding="utf-8", xml_declaration=True)
        temporary_path = Path(temporary.name)
    temporary_path.replace(output)
    print(f"Wrote {len(channel_ids)} channels and {len(programme_ids)} programmes to {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=default_output())
    args = parser.parse_args()
    update(args.output)
