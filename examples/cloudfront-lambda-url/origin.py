import os
from datetime import datetime, timezone


def handler(event, context):
    max_age = os.environ.get("MAX_AGE", "300")
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    body = (
        "<!doctype html><html><head><title>CloudFront demo</title></head><body>"
        "<h1>Hello from Lambda behind CloudFront</h1>"
        f"<p>Generated at {now}. Cached for {max_age} s.</p>"
        "</body></html>"
    )
    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "text/html; charset=utf-8",
            "Cache-Control": f"public, max-age={max_age}",
        },
        "body": body,
    }
