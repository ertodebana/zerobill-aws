"""Fetch and summarize one UTC day of USGS earthquake events."""

import json
import os
import re
from datetime import date, datetime, time, timedelta, timezone
from urllib.parse import urlencode
from urllib.request import Request, urlopen


DATE_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}$")
USGS_QUERY_URL = "https://earthquake.usgs.gov/fdsnws/event/1/query"
MAX_RESPONSE_BYTES = 5 * 1024 * 1024


def _parse_date(value):
    if not isinstance(value, str) or not DATE_PATTERN.fullmatch(value):
        raise ValueError("report_date must use YYYY-MM-DD")
    try:
        return date.fromisoformat(value)
    except ValueError as exc:
        raise ValueError("report_date must be a real calendar date") from exc


def _magnitude(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _magnitude_text(value):
    magnitude = _magnitude(value)
    if magnitude is None:
        return "0"
    return f"{magnitude:g}"


def _event_time(properties):
    timestamp = properties.get("time")
    if not isinstance(timestamp, (int, float)):
        return "--:--"
    return datetime.fromtimestamp(timestamp / 1000, tz=timezone.utc).strftime("%H:%M")


def summarize(geojson, report_date, top_n, retention_days):
    """Return the compact, string-only payload consumed by Step Functions."""
    day = _parse_date(report_date)
    features = geojson.get("features", [])
    if not isinstance(features, list):
        raise ValueError("USGS response features must be a list")

    magnitudes = [
        magnitude
        for feature in features
        if isinstance(feature, dict)
        and isinstance(feature.get("properties"), dict)
        and (magnitude := _magnitude(feature["properties"].get("mag"))) is not None
    ]
    max_mag = _magnitude_text(max(magnitudes)) if magnitudes else "0"

    metadata = geojson.get("metadata", {})
    count_value = metadata.get("count") if isinstance(metadata, dict) else None
    if count_value is None:
        count_value = len(features)
    count = str(count_value)

    ranked = sorted(
        (
            feature
            for feature in features
            if isinstance(feature, dict) and isinstance(feature.get("properties"), dict)
        ),
        key=lambda feature: (
            _magnitude(feature["properties"].get("mag"))
            if _magnitude(feature["properties"].get("mag")) is not None
            else float("-inf"),
            feature["properties"].get("time") or 0,
        ),
        reverse=True,
    )

    lines = [f"Earthquake digest for {day.isoformat()}: {count} events (M2.5+)."]
    if not ranked:
        lines.append("No qualifying events were returned.")
    for feature in ranked[: int(top_n)]:
        properties = feature["properties"]
        place = str(properties.get("place") or "unknown location").replace("\n", " ")
        lines.append(
            f"M{_magnitude_text(properties.get('mag'))} {place} {_event_time(properties)}Z"
        )
    lines.append("Source: USGS Earthquake Hazards Program, https://earthquake.usgs.gov")
    body = "\n".join(lines)
    if len(body.encode("utf-8")) > 4096:
        raise ValueError("digest message exceeds the 4 KB limit")

    expiry = datetime.combine(day, time.min, tzinfo=timezone.utc) + timedelta(
        days=int(retention_days)
    )
    return {
        "report_date": day.isoformat(),
        "prev_date": (day - timedelta(days=1)).isoformat(),
        "count": count,
        "max_mag": max_mag,
        "expires_at": str(int(expiry.timestamp())),
        "body": body,
    }


def handler(event, context):
    """Fetch a single UTC day, defaulting to yesterday for scheduled runs."""
    if not isinstance(event, dict):
        raise ValueError("event must be a JSON object")

    requested_date = event.get("report_date")
    if requested_date is None:
        day = datetime.now(timezone.utc).date() - timedelta(days=1)
    else:
        day = _parse_date(requested_date)

    params = urlencode(
        {
            "format": "geojson",
            "starttime": day.isoformat(),
            "endtime": (day + timedelta(days=1)).isoformat(),
            "minmagnitude": os.environ["MIN_MAGNITUDE"],
            "orderby": "magnitude",
            "limit": 20000,
        }
    )
    request = Request(
        f"{USGS_QUERY_URL}?{params}",
        headers={
            "User-Agent": "daily-digest-example/1.0",
            "Accept": "application/geo+json, application/json",
        },
    )
    with urlopen(request, timeout=8) as response:
        if response.status != 200:
            raise RuntimeError(f"USGS returned HTTP {response.status}")
        payload = response.read(MAX_RESPONSE_BYTES + 1)
    if len(payload) > MAX_RESPONSE_BYTES:
        raise ValueError("USGS response exceeded the 5 MB read cap")

    try:
        geojson = json.loads(payload)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError("USGS returned invalid JSON") from exc
    if not isinstance(geojson, dict):
        raise ValueError("USGS response must be a JSON object")

    result = summarize(
        geojson,
        day.isoformat(),
        int(os.environ["TOP_N"]),
        int(os.environ["RETENTION_DAYS"]),
    )
    print(json.dumps({"report_date": result["report_date"], "count": result["count"]}))
    return result
