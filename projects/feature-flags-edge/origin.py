"""Read feature flags from DynamoDB for the private CloudFront origin."""

import json
import os
import re
from datetime import datetime, timezone
from decimal import Decimal

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError


APP_PATTERN = re.compile(r"/flags/([a-z0-9-]{1,64})")
_table = None


def parse_app(path):
    """Return a lowercase app key for an allowed path, otherwise None."""
    match = APP_PATTERN.fullmatch(path or "")
    return match.group(1) if match else None


def json_value(value):
    if isinstance(value, Decimal):
        if value == value.to_integral_value():
            return int(value)
        return float(value)
    raise TypeError(f"Unsupported JSON value: {type(value).__name__}")


def response(status, body, ttl, cacheable=True):
    headers = {"Content-Type": "application/json"}
    headers["Cache-Control"] = (
        f"public, max-age=0, s-maxage={ttl}" if cacheable else "no-store"
    )
    return {
        "statusCode": status,
        "headers": headers,
        "body": "" if body is None else json.dumps(body, default=json_value),
    }


def get_table():
    """Create the DynamoDB resource on first invocation and reuse it in warm runtimes."""
    global _table
    if _table is None:
        _table = boto3.resource(
            "dynamodb",
            config=Config(retries={"max_attempts": 2, "mode": "standard"}),
        ).Table(os.environ["TABLE_NAME"])
    return _table


def handler(event, _context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "")
    raw_path = event.get("rawPath", "")
    app = parse_app(raw_path)
    ttl = int(os.environ.get("CDN_TTL", "60"))

    if method not in {"GET", "HEAD"}:
        result = response(405, {"error": "method not allowed"}, ttl)
    elif app is None:
        result = response(404, {"error": "not found"}, ttl)
    else:
        try:
            item = get_table().get_item(Key={"app": app}).get("Item")
        except ClientError:
            result = response(503, {"error": "temporarily unavailable"}, ttl, cacheable=False)
        else:
            if item is None:
                result = response(404, {"error": "unknown app"}, ttl)
            else:
                body = {
                    "app": app,
                    "flags": item.get("flags", {}),
                    "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
                }
                result = response(200, body, ttl)

    print(json.dumps({"app": app, "status": result["statusCode"]}))
    if method == "HEAD":
        result["body"] = ""
    return result
