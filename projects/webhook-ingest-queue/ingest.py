"""Verify signed webhook requests and enqueue accepted events."""

import base64
import binascii
import hashlib
import hmac
import json
import os
import re
import time


_secret_cache = None
_secret_fetched_at = 0
_EVENT_ID_RE = re.compile(r"^[A-Za-z0-9_.:-]{1,128}$")
_SIGNATURE_RE = re.compile(r"^sha256=([0-9a-fA-F]{64})$")


def verify(secret: bytes, timestamp: str, body: bytes, signature_header: str, now: int, tolerance: int) -> bool:
    """Check timestamp and HMAC-SHA256 signature for the exact raw request body."""
    if not isinstance(timestamp, str) or not timestamp.isascii() or not timestamp.isdecimal():
        return False
    try:
        signed_at = int(timestamp)
    except (TypeError, ValueError):
        return False
    if abs(now - signed_at) > tolerance:
        return False

    match = _SIGNATURE_RE.fullmatch(signature_header or "")
    if match is None:
        return False
    expected = hmac.new(secret, timestamp.encode("ascii") + b"." + body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, match.group(1).lower())


def _response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body, separators=(",", ":")),
    }


def _load_secret(now: int) -> str:
    global _secret_cache, _secret_fetched_at
    if _secret_cache is not None and now - _secret_fetched_at < 300:
        return _secret_cache

    import boto3

    response = boto3.client("ssm").get_parameter(
        Name=os.environ["SECRET_PARAM"], WithDecryption=True
    )
    _secret_cache = response["Parameter"]["Value"]
    _secret_fetched_at = now
    return _secret_cache


def _log(event_id: str, outcome: str) -> None:
    # Do not log the body, signature, or secret.
    print(json.dumps({"event_id": event_id or "-", "outcome": outcome}, separators=(",", ":")))


def handler(event, context):
    event_id = ""
    method = event.get("requestContext", {}).get("http", {}).get("method", "")
    if method != "POST":
        _log(event_id, "method_not_allowed")
        return _response(405, {"error": "method not allowed"})

    headers = {str(key).lower(): value for key, value in (event.get("headers") or {}).items()}
    event_id = str(headers.get("x-webhook-id", ""))
    timestamp = str(headers.get("x-webhook-timestamp", ""))
    signature = str(headers.get("x-webhook-signature", ""))
    if not _EVENT_ID_RE.fullmatch(event_id) or not timestamp.isascii() or not timestamp.isdecimal() or not signature:
        _log(event_id, "invalid_headers")
        return _response(400, {"error": "missing or malformed webhook headers"})

    body_text = event.get("body") or ""
    try:
        body = base64.b64decode(body_text, validate=True) if event.get("isBase64Encoded") else body_text.encode("utf-8")
    except (binascii.Error, UnicodeEncodeError):
        _log(event_id, "invalid_body_encoding")
        return _response(400, {"error": "invalid body encoding"})

    max_body_bytes = int(os.environ["MAX_BODY_BYTES"])
    if len(body) > max_body_bytes:
        _log(event_id, "body_too_large")
        return _response(413, {"error": "body too large"})

    now = int(time.time())
    tolerance = int(os.environ["TOLERANCE_SECONDS"])
    if abs(now - int(timestamp)) > tolerance:
        _log(event_id, "timestamp_out_of_window")
        return _response(401, {"error": "timestamp outside allowed window"})

    try:
        secret = _load_secret(now)
    except Exception as exc:  # AWS errors are intentionally not returned to the caller.
        print(json.dumps({"event_id": event_id, "outcome": "secret_unavailable", "error_type": type(exc).__name__}))
        return _response(503, {"error": "webhook secret unavailable"})
    if not secret or secret == os.environ.get("PLACEHOLDER", "REPLACE_ME"):
        _log(event_id, "secret_not_configured")
        return _response(503, {"error": "webhook secret is not configured"})

    if not verify(secret.encode("utf-8"), timestamp, body, signature, now, tolerance):
        _log(event_id, "signature_rejected")
        return _response(401, {"error": "invalid signature"})

    try:
        payload = json.loads(body)
    except (json.JSONDecodeError, UnicodeDecodeError):
        _log(event_id, "invalid_json")
        return _response(400, {"error": "body must be valid JSON"})

    try:
        import boto3

        boto3.client("sqs").send_message(
            QueueUrl=os.environ["QUEUE_URL"],
            MessageBody=json.dumps(
                {"event_id": event_id, "received_at": now, "payload": payload},
                separators=(",", ":"),
            ),
        )
    except Exception as exc:
        print(json.dumps({"event_id": event_id, "outcome": "queue_send_failed", "error_type": type(exc).__name__}))
        return _response(500, {"error": "could not enqueue webhook"})

    _log(event_id, "accepted")
    return _response(202, {"accepted": event_id})
